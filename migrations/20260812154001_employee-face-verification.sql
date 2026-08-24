create table public.employee_face_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  model_version text not null,
  descriptor jsonb not null,
  sample_count integer not null check (sample_count between 1 and 10),
  match_threshold numeric(5,4) not null default 0.5500 check (match_threshold between 0.1 and 0.99),
  enrolled_by uuid not null references auth.users(id) on delete restrict,
  enrolled_at timestamptz not null default now(),
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  revocation_reason text,
  check (jsonb_typeof(descriptor) = 'array'),
  check (jsonb_array_length(descriptor) = 512),
  check ((revoked_at is null and revoked_by is null) or revoked_at is not null)
);

create unique index employee_face_templates_active_idx
  on public.employee_face_templates(employee_id)
  where revoked_at is null;
create index employee_face_templates_org_idx
  on public.employee_face_templates(organization_id, enrolled_at desc);

create table public.face_verification_proofs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  template_id uuid not null references public.employee_face_templates(id) on delete restrict,
  device_id text not null check (length(device_id) between 8 and 200),
  model_version text not null,
  similarity numeric(6,5) not null,
  liveness_passed boolean not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create index face_verification_proofs_lookup_idx
  on public.face_verification_proofs(user_id, branch_id, expires_at desc)
  where consumed_at is null;

alter table public.attendance_attempts
  add column device_id text,
  add column biometric_proof_id uuid references public.face_verification_proofs(id) on delete set null;

create or replace function public.face_template_status(
  p_actor_user_id uuid,
  p_employee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  e public.employees%rowtype;
  t public.employee_face_templates%rowtype;
  allowed boolean := false;
begin
  select * into e from public.employees where id = p_employee_id;
  if e.id is null then raise exception 'employee not found'; end if;

  allowed := e.user_id = p_actor_user_id
    or exists(
      select 1 from public.organization_memberships om
      where om.organization_id = e.organization_id
        and om.user_id = p_actor_user_id
        and om.is_active
        and om.role in ('owner','super_admin','hr_admin')
    )
    or exists(
      select 1
      from public.employee_branch_assignments a
      join public.branch_memberships bm on bm.branch_id = a.branch_id
      where a.employee_id = e.id
        and a.starts_on <= current_date
        and (a.ends_on is null or a.ends_on >= current_date)
        and bm.user_id = p_actor_user_id
        and bm.is_active
        and bm.role in ('manager','branch_admin')
    );
  if not allowed then raise exception 'not permitted'; end if;

  select * into t
  from public.employee_face_templates
  where employee_id = e.id and revoked_at is null;

  return jsonb_build_object(
    'employeeId', e.id,
    'enrolled', t.id is not null,
    'enrolledAt', t.enrolled_at,
    'modelVersion', t.model_version
  );
end;
$$;

create or replace function public.enroll_employee_face(
  p_actor_user_id uuid,
  p_employee_id uuid,
  p_model_version text,
  p_descriptor jsonb,
  p_sample_count integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  e public.employees%rowtype;
  new_template public.employee_face_templates%rowtype;
  audit_branch_id uuid;
  allowed boolean := false;
  descriptor_norm numeric;
begin
  if p_model_version <> 'adaface_ir18_v1' then raise exception 'unsupported face model'; end if;
  if p_sample_count < 3 or p_sample_count > 10 then raise exception 'three face samples are required'; end if;
  if jsonb_typeof(p_descriptor) <> 'array' or jsonb_array_length(p_descriptor) <> 512 then
    raise exception 'invalid face descriptor';
  end if;
  if exists(select 1 from jsonb_array_elements(p_descriptor) v(value) where jsonb_typeof(v.value) <> 'number') then
    raise exception 'invalid face descriptor values';
  end if;
  select sqrt(sum(power(value::text::numeric, 2))) into descriptor_norm
  from jsonb_array_elements(p_descriptor);
  if descriptor_norm < 0.95 or descriptor_norm > 1.05 then raise exception 'face descriptor is not normalized'; end if;

  select * into e from public.employees where id = p_employee_id and employment_status = 'active';
  if e.id is null then raise exception 'active employee not found'; end if;

  allowed := exists(
      select 1 from public.organization_memberships om
      where om.organization_id = e.organization_id
        and om.user_id = p_actor_user_id
        and om.is_active
        and om.role in ('owner','super_admin','hr_admin')
    )
    or exists(
      select 1
      from public.employee_branch_assignments a
      join public.branch_memberships bm on bm.branch_id = a.branch_id
      where a.employee_id = e.id
        and a.starts_on <= current_date
        and (a.ends_on is null or a.ends_on >= current_date)
        and bm.user_id = p_actor_user_id
        and bm.is_active
        and bm.role in ('manager','branch_admin')
    );
  if not allowed then raise exception 'not permitted'; end if;

  select a.branch_id into audit_branch_id
  from public.employee_branch_assignments a
  where a.employee_id = e.id
    and a.starts_on <= current_date
    and (a.ends_on is null or a.ends_on >= current_date)
  order by a.is_primary desc, a.starts_on desc
  limit 1;

  perform pg_advisory_xact_lock(hashtext(e.id::text));
  update public.employee_face_templates
  set revoked_at = now(), revoked_by = p_actor_user_id, revocation_reason = 'Replaced by new enrollment'
  where employee_id = e.id and revoked_at is null;

  insert into public.employee_face_templates(
    organization_id, employee_id, model_version, descriptor, sample_count, enrolled_by
  ) values (
    e.organization_id, e.id, p_model_version, p_descriptor, p_sample_count, p_actor_user_id
  ) returning * into new_template;

  insert into public.audit_events(
    organization_id, branch_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    e.organization_id, audit_branch_id, p_actor_user_id, 'face.enrolled', 'employee', e.id,
    jsonb_build_object('template_id', new_template.id, 'model_version', p_model_version, 'sample_count', p_sample_count)
  );

  return jsonb_build_object(
    'employeeId', e.id,
    'enrolled', true,
    'enrolledAt', new_template.enrolled_at,
    'modelVersion', new_template.model_version
  );
end;
$$;

create or replace function public.revoke_employee_face(
  p_actor_user_id uuid,
  p_employee_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  e public.employees%rowtype;
  t public.employee_face_templates%rowtype;
  audit_branch_id uuid;
  allowed boolean := false;
begin
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'revocation reason is required'; end if;
  select * into e from public.employees where id = p_employee_id;
  if e.id is null then raise exception 'employee not found'; end if;

  allowed := exists(
      select 1 from public.organization_memberships om
      where om.organization_id = e.organization_id
        and om.user_id = p_actor_user_id
        and om.is_active
        and om.role in ('owner','super_admin','hr_admin')
    )
    or exists(
      select 1
      from public.employee_branch_assignments a
      join public.branch_memberships bm on bm.branch_id = a.branch_id
      where a.employee_id = e.id
        and a.starts_on <= current_date
        and (a.ends_on is null or a.ends_on >= current_date)
        and bm.user_id = p_actor_user_id
        and bm.is_active
        and bm.role in ('manager','branch_admin')
    );
  if not allowed then raise exception 'not permitted'; end if;

  select a.branch_id into audit_branch_id
  from public.employee_branch_assignments a
  where a.employee_id = e.id
    and a.starts_on <= current_date
    and (a.ends_on is null or a.ends_on >= current_date)
  order by a.is_primary desc, a.starts_on desc
  limit 1;

  select * into t
  from public.employee_face_templates
  where employee_id = e.id and revoked_at is null
  for update;
  if t.id is null then return jsonb_build_object('employeeId', e.id, 'enrolled', false); end if;

  update public.employee_face_templates
  set revoked_at = now(), revoked_by = p_actor_user_id, revocation_reason = trim(p_reason)
  where id = t.id;
  update public.face_verification_proofs
  set consumed_at = coalesce(consumed_at, now())
  where template_id = t.id and consumed_at is null;

  insert into public.audit_events(
    organization_id, branch_id, actor_user_id, action, entity_type, entity_id, reason,
    metadata
  ) values (
    e.organization_id, audit_branch_id, p_actor_user_id, 'face.revoked', 'employee', e.id,
    trim(p_reason), jsonb_build_object('template_id', t.id)
  );

  return jsonb_build_object('employeeId', e.id, 'enrolled', false);
end;
$$;

create or replace function public.verify_employee_face(
  p_actor_user_id uuid,
  p_branch_id uuid,
  p_device_id text,
  p_model_version text,
  p_descriptor jsonb,
  p_liveness_passed boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  b public.branches%rowtype;
  e public.employees%rowtype;
  t public.employee_face_templates%rowtype;
  proof public.face_verification_proofs%rowtype;
  similarity numeric;
  candidate_norm numeric;
  template_norm numeric;
  dot_product numeric;
begin
  if length(trim(coalesce(p_device_id, ''))) < 8 then raise exception 'invalid device identifier'; end if;
  if p_model_version <> 'adaface_ir18_v1' then raise exception 'unsupported face model'; end if;
  if not coalesce(p_liveness_passed, false) then
    return jsonb_build_object('matched', false, 'reason', 'liveness_required');
  end if;
  if jsonb_typeof(p_descriptor) <> 'array' or jsonb_array_length(p_descriptor) <> 512 then
    raise exception 'invalid face descriptor';
  end if;
  if exists(select 1 from jsonb_array_elements(p_descriptor) v(value) where jsonb_typeof(v.value) <> 'number') then
    raise exception 'invalid face descriptor values';
  end if;

  select * into b from public.branches where id = p_branch_id and is_active;
  if b.id is null then raise exception 'branch not found'; end if;
  select * into e
  from public.employees
  where user_id = p_actor_user_id
    and organization_id = b.organization_id
    and employment_status = 'active';
  if e.id is null then raise exception 'active employee not found'; end if;
  if not exists(
    select 1 from public.employee_branch_assignments a
    where a.employee_id = e.id and a.branch_id = b.id
      and a.starts_on <= current_date
      and (a.ends_on is null or a.ends_on >= current_date)
  ) then raise exception 'employee is not assigned to this branch'; end if;

  select * into t
  from public.employee_face_templates
  where employee_id = e.id and revoked_at is null;
  if t.id is null then
    return jsonb_build_object('matched', false, 'reason', 'face_not_enrolled');
  end if;
  if t.model_version <> p_model_version then
    return jsonb_build_object('matched', false, 'reason', 'face_model_changed');
  end if;

  select
    sum(c.value::text::numeric * r.value::text::numeric),
    sqrt(sum(power(c.value::text::numeric, 2))),
    sqrt(sum(power(r.value::text::numeric, 2)))
  into dot_product, candidate_norm, template_norm
  from jsonb_array_elements(p_descriptor) with ordinality c(value, position)
  join jsonb_array_elements(t.descriptor) with ordinality r(value, position)
    using (position);
  if candidate_norm < 0.95 or candidate_norm > 1.05 or template_norm = 0 then
    raise exception 'face descriptor is not normalized';
  end if;
  similarity := dot_product / (candidate_norm * template_norm);

  if similarity < t.match_threshold then
    insert into public.audit_events(
      organization_id, branch_id, actor_user_id, action, entity_type, entity_id, metadata
    ) values (
      e.organization_id, b.id, p_actor_user_id, 'face.verification_failed', 'employee', e.id,
      jsonb_build_object('similarity', round(similarity, 5), 'model_version', p_model_version, 'device_id', p_device_id)
    );
    return jsonb_build_object('matched', false, 'reason', 'face_not_matched');
  end if;

  insert into public.face_verification_proofs(
    organization_id, branch_id, employee_id, user_id, template_id, device_id,
    model_version, similarity, liveness_passed, expires_at
  ) values (
    e.organization_id, b.id, e.id, p_actor_user_id, t.id, p_device_id,
    p_model_version, similarity, true, now() + interval '2 minutes'
  ) returning * into proof;

  insert into public.audit_events(
    organization_id, branch_id, actor_user_id, action, entity_type, entity_id, metadata
  ) values (
    e.organization_id, b.id, p_actor_user_id, 'face.verified', 'employee', e.id,
    jsonb_build_object('proof_id', proof.id, 'similarity', round(similarity, 5), 'model_version', p_model_version, 'device_id', p_device_id)
  );

  return jsonb_build_object(
    'matched', true,
    'proofId', proof.id,
    'expiresAt', proof.expires_at,
    'similarity', round(similarity, 5)
  );
end;
$$;

create or replace function public.process_attendance_with_face_proof(
  p_actor_user_id uuid,
  p_request_id uuid,
  p_branch_id uuid,
  p_event_type text,
  p_source_ip inet,
  p_latitude numeric,
  p_longitude numeric,
  p_gps_accuracy_m numeric,
  p_biometric_proof_id uuid,
  p_device_id text,
  p_override_employee_id uuid default null,
  p_override_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  b public.branches%rowtype;
  e public.employees%rowtype;
  proof public.face_verification_proofs%rowtype;
  existing_attempt public.attendance_attempts%rowtype;
  result jsonb;
  result_attempt_id uuid;
begin
  select * into existing_attempt from public.attendance_attempts where request_id = p_request_id;
  if existing_attempt.id is not null then
    return jsonb_build_object(
      'accepted', existing_attempt.outcome = 'accepted',
      'attempt_id', existing_attempt.id,
      'rejection_code', existing_attempt.rejection_code,
      'distance_m', existing_attempt.distance_m,
      'ip_passed', existing_attempt.ip_passed,
      'gps_passed', existing_attempt.gps_passed
    );
  end if;

  if p_override_employee_id is not null then
    result := public.process_attendance(
      p_actor_user_id, p_request_id, p_branch_id, p_event_type, p_source_ip,
      p_latitude, p_longitude, p_gps_accuracy_m, false,
      p_override_employee_id, p_override_reason
    );
    result_attempt_id := nullif(result->>'attempt_id', '')::uuid;
    update public.attendance_attempts set device_id = p_device_id where id = result_attempt_id;
    return result;
  end if;

  select * into b from public.branches where id = p_branch_id and is_active;
  if b.id is null then raise exception 'branch not found'; end if;
  select * into e
  from public.employees
  where user_id = p_actor_user_id
    and organization_id = b.organization_id
    and employment_status = 'active';
  if e.id is null then raise exception 'active employee not found'; end if;

  if b.requires_biometric then
    select * into proof
    from public.face_verification_proofs
    where id = p_biometric_proof_id
      and user_id = p_actor_user_id
      and employee_id = e.id
      and branch_id = b.id
      and device_id = p_device_id
      and liveness_passed
      and consumed_at is null
      and expires_at > now()
    for update;
  end if;

  if b.requires_biometric and proof.id is null then
    result := public.process_attendance(
      p_actor_user_id, p_request_id, p_branch_id, p_event_type, p_source_ip,
      p_latitude, p_longitude, p_gps_accuracy_m, false, null, null
    );
  else
    if proof.id is not null then
      update public.face_verification_proofs set consumed_at = now() where id = proof.id;
    end if;
    result := public.process_attendance(
      p_actor_user_id, p_request_id, p_branch_id, p_event_type, p_source_ip,
      p_latitude, p_longitude, p_gps_accuracy_m, proof.id is not null, null, null
    );
  end if;

  result_attempt_id := nullif(result->>'attempt_id', '')::uuid;
  update public.attendance_attempts
  set device_id = p_device_id, biometric_proof_id = proof.id
  where id = result_attempt_id;
  return result;
end;
$$;

alter table public.employee_face_templates enable row level security;
alter table public.face_verification_proofs enable row level security;

revoke all on public.employee_face_templates, public.face_verification_proofs from public, anon, authenticated;
revoke all on function public.face_template_status(uuid,uuid) from public, anon, authenticated;
revoke all on function public.enroll_employee_face(uuid,uuid,text,jsonb,integer) from public, anon, authenticated;
revoke all on function public.revoke_employee_face(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.verify_employee_face(uuid,uuid,text,text,jsonb,boolean) from public, anon, authenticated;
revoke all on function public.process_attendance_with_face_proof(uuid,uuid,uuid,text,inet,numeric,numeric,numeric,uuid,text,uuid,text) from public, anon, authenticated;

comment on table public.employee_face_templates is
  'Private mathematical face embeddings only. Raw photos and video must never be stored.';
comment on column public.employee_face_templates.descriptor is
  'L2-normalized 512-value AdaFace embedding; inaccessible to mobile clients.';
