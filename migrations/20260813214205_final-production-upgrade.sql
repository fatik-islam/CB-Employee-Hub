-- Final iOS production upgrade.
-- The product intentionally exposes exactly three roles: owner, manager and staff.
-- "employee" remains the stored identifier for the user-facing Staff role so older
-- invitations and installed clients continue to work during the rollout.

update public.organization_memberships
set role='manager'
where role in ('super_admin','hr_admin','payroll_admin','payroll_approver');

update public.branch_memberships set role='manager' where role='branch_admin';

alter table public.organization_memberships drop constraint if exists organization_memberships_role_check;
alter table public.organization_memberships
  add constraint organization_memberships_role_check check(role in ('owner','manager','employee'));

alter table public.branch_memberships drop constraint if exists branch_memberships_role_check;
alter table public.branch_memberships
  add constraint branch_memberships_role_check check(role in ('manager','employee'));

create or replace function public.can_manage_branch(target_branch uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp
as $$
  select exists(
    select 1 from public.branch_memberships bm
    where bm.branch_id=target_branch and bm.user_id=auth.uid()
      and bm.is_active and bm.role='manager'
  ) or exists(
    select 1 from public.branches b
    where b.id=target_branch and public.has_org_role(b.organization_id,array['owner'])
  );
$$;

create or replace function public.can_manage_payroll(target_org uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp
as $$ select public.has_org_role(target_org,array['owner']); $$;

-- Branch-owned kiosk devices use an authenticated owner/manager session, but the
-- public screen never exposes account switching or manager operations.
create table public.branch_kiosk_devices(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  device_id text not null,
  device_name text not null,
  registered_by uuid not null references auth.users(id) on delete restrict,
  is_active boolean not null default true,
  registered_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz,
  unique(branch_id,device_id)
);

alter table public.branch_kiosk_devices enable row level security;
create policy branch_kiosk_read on public.branch_kiosk_devices for select to authenticated
  using(public.can_manage_branch(branch_id));
create policy branch_kiosk_manage on public.branch_kiosk_devices for all to authenticated
  using(public.can_manage_branch(branch_id)) with check(public.can_manage_branch(branch_id));
grant select,insert,update on public.branch_kiosk_devices to authenticated;
revoke delete on public.branch_kiosk_devices from anon,authenticated;

create index branch_kiosk_org_idx on public.branch_kiosk_devices(organization_id);
create index branch_kiosk_registered_by_idx on public.branch_kiosk_devices(registered_by);
create index branch_kiosk_active_idx on public.branch_kiosk_devices(branch_id,is_active,device_id);

create or replace function public.register_branch_kiosk(p_branch_id uuid,p_device_id text,p_device_name text)
returns public.branch_kiosk_devices language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare result public.branch_kiosk_devices%rowtype;org uuid;
begin
  if auth.uid() is null or not public.can_manage_branch(p_branch_id) then raise exception 'not permitted';end if;
  if length(trim(coalesce(p_device_id,'')))<8 then raise exception 'invalid device';end if;
  if not exists(select 1 from public.trusted_devices where user_id=auth.uid() and device_id=p_device_id and is_active and revoked_at is null) then
    raise exception 'trusted device registration required';
  end if;
  select organization_id into org from public.branches where id=p_branch_id and is_active;
  if org is null then raise exception 'branch not found';end if;
  insert into public.branch_kiosk_devices(organization_id,branch_id,device_id,device_name,registered_by)
  values(org,p_branch_id,trim(p_device_id),left(coalesce(nullif(trim(p_device_name),''),'Attendance device'),80),auth.uid())
  on conflict(branch_id,device_id) do update set device_name=excluded.device_name,registered_by=auth.uid(),is_active=true,revoked_at=null
  returning * into result;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(org,p_branch_id,auth.uid(),'kiosk.registered','kiosk_device',result.id,jsonb_build_object('device_name',result.device_name));
  return result;
end $$;

create or replace function public.deactivate_branch_kiosk(p_kiosk_id uuid)
returns boolean language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare kiosk public.branch_kiosk_devices%rowtype;
begin
  select * into kiosk from public.branch_kiosk_devices where id=p_kiosk_id for update;
  if kiosk.id is null or not public.can_manage_branch(kiosk.branch_id) then raise exception 'not permitted';end if;
  update public.branch_kiosk_devices set is_active=false,revoked_at=now() where id=kiosk.id;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id)
  values(kiosk.organization_id,kiosk.branch_id,auth.uid(),'kiosk.deactivated','kiosk_device',kiosk.id);
  return true;
end $$;

-- Device integrity metadata. The existing P-256 key remains the authoritative
-- offline evidence key; DeviceCheck adds an independent Apple-issued signal.
alter table public.trusted_devices
  add column integrity_provider text,
  add column integrity_state text not null default 'not_checked'
    check(integrity_state in ('not_checked','verified','unavailable','failed')),
  add column integrity_checked_at timestamptz;

create index trusted_devices_integrity_idx on public.trusted_devices(organization_id,integrity_state,is_active);

create or replace function public.set_device_integrity_result(
  p_user_id uuid,p_device_id text,p_provider text,p_state text
) returns boolean language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
begin
  if p_state not in ('verified','unavailable','failed') then raise exception 'invalid integrity state';end if;
  update public.trusted_devices set integrity_provider=left(p_provider,40),integrity_state=p_state,integrity_checked_at=now(),last_seen_at=now()
  where user_id=p_user_id and device_id=p_device_id and is_active and revoked_at is null;
  return found;
end $$;
revoke execute on function public.set_device_integrity_result(uuid,text,text,text) from public,anon,authenticated;

-- Break-aware attendance and timesheet fields.
alter table public.attendance_daily
  add column break_minutes integer not null default 0 check(break_minutes>=0),
  add column active_break_started_at timestamptz;

alter table public.attendance_attempts drop constraint if exists attendance_attempts_event_type_check;
alter table public.attendance_attempts add constraint attendance_attempts_event_type_check
  check(event_type in ('check_in','break_start','break_end','check_out'));
alter table public.attendance_events drop constraint if exists attendance_events_event_type_check;
alter table public.attendance_events add constraint attendance_events_event_type_check
  check(event_type in ('check_in','break_start','break_end','check_out'));
alter table public.attendance_events drop constraint if exists attendance_events_source_check;
alter table public.attendance_events add constraint attendance_events_source_check
  check(source in ('employee_app','manager_override','kiosk_device','legacy_import','offline_verified'));

create index attendance_events_daily_sequence_idx
  on public.attendance_events(employee_id,branch_id,local_work_date,occurred_at,id);

-- Full reusable schedule policies. Existing weekly_rules remain compatible; each
-- day may additionally provide start/end/break/secondStart/secondEnd values.
alter table public.schedule_templates
  add column is_overnight boolean not null default false,
  add column is_split_shift boolean not null default false,
  add column notes text;

create or replace function public.employee_schedule_for_date(p_employee uuid,p_date date)
returns jsonb language sql stable security definer
set search_path=pg_catalog,public,pg_temp
as $$
  with selected as(
    select st.* from public.employee_schedule_assignments esa
    join public.schedule_templates st on st.id=esa.schedule_template_id
    where esa.employee_id=p_employee and esa.effective_from<=p_date
      and (esa.effective_to is null or esa.effective_to>=p_date) and st.is_active
    order by esa.effective_from desc limit 1
  ), day_rule as(
    select s.*,(s.weekly_rules->extract(isodow from p_date)::int::text) rule from selected s
  )
  select jsonb_build_object(
    'working',coalesce((rule->>'working')::boolean,true),
    'start',coalesce(rule->>'start',check_in_time::text),
    'end',coalesce(rule->>'end',check_out_time::text),
    'breakMinutes',coalesce((rule->>'breakMinutes')::integer,break_minutes),
    'graceMinutes',grace_minutes,
    'expectedMinutes',coalesce((rule->>'expectedMinutes')::integer,expected_minutes_per_day),
    'overtimeAfterMinutes',overtime_after_minutes,
    'secondStart',rule->>'secondStart','secondEnd',rule->>'secondEnd',
    'overnight',coalesce((rule->>'overnight')::boolean,is_overnight),
    'templateId',id,'templateName',name
  ) from day_rule;
$$;

revoke execute on function public.employee_schedule_for_date(uuid,date) from public,anon;
grant execute on function public.employee_schedule_for_date(uuid,date) to authenticated;

create or replace function public.recalculate_attendance_day(p_employee uuid,p_branch uuid,p_work_date date)
returns public.attendance_daily language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare org uuid;first_in timestamptz;last_out timestamptz;active_break timestamptz;break_total integer:=0;
  gross integer:=0;worked integer:=0;schedule jsonb;scheduled integer:=0;late integer:=0;overtime integer:=0;shortfall integer:=0;
  schedule_start timestamptz;result public.attendance_daily%rowtype;
begin
  select organization_id into org from public.branches where id=p_branch;
  select min(occurred_at) filter(where event_type='check_in'),max(occurred_at) filter(where event_type='check_out')
    into first_in,last_out from public.attendance_events
    where employee_id=p_employee and branch_id=p_branch and local_work_date=p_work_date;
  with ordered as(
    select event_type,occurred_at,lead(event_type) over(order by occurred_at,id) next_type,
      lead(occurred_at) over(order by occurred_at,id) next_at
    from public.attendance_events where employee_id=p_employee and branch_id=p_branch and local_work_date=p_work_date
  ) select coalesce(sum(greatest(0,floor(extract(epoch from(next_at-occurred_at))/60)::integer))
      filter(where event_type='break_start' and next_type='break_end'),0)
    into break_total from ordered;
  select occurred_at into active_break from public.attendance_events
    where employee_id=p_employee and branch_id=p_branch and local_work_date=p_work_date
      and event_type='break_start' and not exists(
        select 1 from public.attendance_events later where later.employee_id=p_employee and later.branch_id=p_branch
          and later.local_work_date=p_work_date and later.event_type='break_end' and later.occurred_at>attendance_events.occurred_at)
    order by occurred_at desc limit 1;
  schedule:=coalesce(public.employee_schedule_for_date(p_employee,p_work_date),'{}'::jsonb);
  scheduled:=coalesce((schedule->>'expectedMinutes')::integer,0);
  if first_in is not null and last_out is not null then gross:=greatest(0,floor(extract(epoch from(last_out-first_in))/60)::integer);end if;
  worked:=greatest(0,gross-break_total);
  if first_in is not null and schedule ? 'start' then
    schedule_start:=((p_work_date::text||' '||(schedule->>'start'))::timestamp at time zone (select timezone from public.branches where id=p_branch));
    late:=greatest(0,floor(extract(epoch from(first_in-schedule_start))/60)::integer-coalesce((schedule->>'graceMinutes')::integer,0));
  end if;
  if last_out is not null then
    overtime:=greatest(0,worked-coalesce((schedule->>'overtimeAfterMinutes')::integer,scheduled));
    shortfall:=greatest(0,scheduled-worked);
  end if;
  insert into public.attendance_daily(organization_id,branch_id,employee_id,work_date,first_check_in_at,last_check_out_at,
    worked_minutes,break_minutes,active_break_started_at,scheduled_minutes,late_minutes,overtime_minutes,shortfall_minutes,status)
  values(org,p_branch,p_employee,p_work_date,first_in,last_out,worked,break_total,active_break,scheduled,late,overtime,shortfall,
    case when first_in is null then 'absent' when last_out is null then 'present' when worked<scheduled then 'partial' else 'present' end)
  on conflict(employee_id,work_date) do update set branch_id=excluded.branch_id,first_check_in_at=excluded.first_check_in_at,
    last_check_out_at=excluded.last_check_out_at,worked_minutes=excluded.worked_minutes,break_minutes=excluded.break_minutes,
    active_break_started_at=excluded.active_break_started_at,scheduled_minutes=excluded.scheduled_minutes,late_minutes=excluded.late_minutes,
    overtime_minutes=excluded.overtime_minutes,shortfall_minutes=excluded.shortfall_minutes,status=excluded.status
  returning * into result;
  return result;
end $$;
revoke execute on function public.recalculate_attendance_day(uuid,uuid,date) from public,anon,authenticated;

create or replace function public.recalculate_attendance_after_event()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$ begin perform public.recalculate_attendance_day(new.employee_id,new.branch_id,new.local_work_date);return new;end $$;
drop trigger if exists attendance_events_recalculate_day on public.attendance_events;
create trigger attendance_events_recalculate_day after insert on public.attendance_events
for each row execute function public.recalculate_attendance_after_event();

create or replace function public.record_attendance_event(
  p_actor_user_id uuid,p_request_id uuid,p_branch_id uuid,p_employee_id uuid,p_event_type text,
  p_source_ip inet,p_latitude numeric,p_longitude numeric,p_gps_accuracy_m numeric,
  p_biometric_passed boolean,p_source text,p_used_override boolean default false,p_override_reason text default null
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare b public.branches%rowtype;e public.employees%rowtype;attempt public.attendance_attempts%rowtype;
  day public.attendance_daily%rowtype;event_id uuid;ip_ok boolean:=false;gps_ok boolean:=false;dist numeric;
  work_day date;reject_code text;now_at timestamptz:=now();
begin
  if p_event_type not in ('check_in','break_start','break_end','check_out') then raise exception 'invalid event type';end if;
  if p_source not in ('employee_app','manager_override','kiosk_device') then raise exception 'invalid attendance source';end if;
  select * into attempt from public.attendance_attempts where request_id=p_request_id;
  if attempt.id is not null then return jsonb_build_object('accepted',attempt.outcome='accepted','attempt_id',attempt.id,'rejection_code',attempt.rejection_code);end if;
  select * into b from public.branches where id=p_branch_id and is_active;
  select * into e from public.employees where id=p_employee_id and organization_id=b.organization_id and employment_status='active';
  if b.id is null or e.id is null then raise exception 'active employee or branch not found';end if;
  if not exists(select 1 from public.employee_branch_assignments a where a.employee_id=e.id and a.branch_id=b.id
    and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date)) then raise exception 'employee is not assigned to this branch';end if;
  work_day:=(now_at at time zone b.timezone)::date;
  if p_event_type<>'check_in' then
    select * into day from public.attendance_daily where employee_id=e.id and branch_id=b.id
      and first_check_in_at is not null and last_check_out_at is null and first_check_in_at>now_at-interval '20 hours'
      order by work_date desc limit 1;
    if day.id is not null then work_day:=day.work_date;end if;
  else
    select * into day from public.attendance_daily where employee_id=e.id and branch_id=b.id and work_date=work_day;
  end if;
  if day.id is null then select * into day from public.attendance_daily where employee_id=e.id and branch_id=b.id and work_date=work_day;end if;

  if p_event_type='check_in' and day.first_check_in_at is not null and day.last_check_out_at is null then reject_code:='already_checked_in';
  elsif p_event_type='check_in' and day.last_check_out_at is not null then reject_code:='attendance_complete';
  elsif p_event_type='break_start' and (day.first_check_in_at is null or day.last_check_out_at is not null) then reject_code:='not_checked_in';
  elsif p_event_type='break_start' and day.active_break_started_at is not null then reject_code:='break_already_started';
  elsif p_event_type='break_end' and day.active_break_started_at is null then reject_code:='no_active_break';
  elsif p_event_type='check_out' and day.first_check_in_at is null then reject_code:='not_checked_in';
  elsif p_event_type='check_out' and day.active_break_started_at is not null then reject_code:='end_break_first';
  elsif p_event_type='check_out' and day.last_check_out_at is not null then reject_code:='already_checked_out';end if;

  select exists(select 1 from public.branch_ip_rules r where r.branch_id=b.id and r.is_active
    and (r.valid_from is null or r.valid_from<=now_at) and (r.valid_until is null or r.valid_until>=now_at)
    and p_source_ip <<= r.network) into ip_ok;
  dist:=public.distance_metres(b.latitude,b.longitude,p_latitude,p_longitude);
  gps_ok:=dist is not null and p_gps_accuracy_m is not null and p_gps_accuracy_m<=b.gps_accuracy_limit_m and dist<=b.geofence_radius_m;
  if not p_used_override and reject_code is null then
    if b.requires_biometric and not coalesce(p_biometric_passed,false) then reject_code:='biometric_required';
    elsif b.attendance_verification_mode='IP_ONLY' and not ip_ok then reject_code:='ip_not_allowed';
    elsif b.attendance_verification_mode='GPS_ONLY' and not gps_ok then reject_code:='outside_geofence';
    elsif b.attendance_verification_mode='IP_OR_GPS' and not(ip_ok or gps_ok) then reject_code:='location_not_verified';
    elsif b.attendance_verification_mode='IP_AND_GPS' and not(ip_ok and gps_ok) then reject_code:='both_ip_and_gps_required';end if;
  end if;
  insert into public.attendance_attempts(request_id,organization_id,branch_id,employee_id,actor_user_id,event_type,source_ip,
    latitude,longitude,gps_accuracy_m,distance_m,ip_passed,gps_passed,biometric_passed,used_override,outcome,rejection_code)
  values(p_request_id,b.organization_id,b.id,e.id,p_actor_user_id,p_event_type,p_source_ip,p_latitude,p_longitude,p_gps_accuracy_m,
    dist,ip_ok,gps_ok,coalesce(p_biometric_passed,false),p_used_override,case when reject_code is null then 'accepted' else 'rejected' end,reject_code)
  returning * into attempt;
  if reject_code is not null then return jsonb_build_object('accepted',false,'attempt_id',attempt.id,'rejection_code',reject_code,'distance_m',dist,'ip_passed',ip_ok,'gps_passed',gps_ok);end if;
  insert into public.attendance_events(attempt_id,organization_id,branch_id,employee_id,event_type,occurred_at,local_work_date,source)
  values(attempt.id,b.organization_id,b.id,e.id,p_event_type,now_at,work_day,p_source) returning id into event_id;
  if p_used_override then
    insert into public.attendance_overrides(organization_id,branch_id,employee_id,manager_user_id,event_type,reason,attendance_event_id)
    values(b.organization_id,b.id,e.id,p_actor_user_id,p_event_type,trim(p_override_reason),event_id);
    insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,reason)
    values(b.organization_id,b.id,p_actor_user_id,'attendance.override','attendance_event',event_id,trim(p_override_reason));
  elsif p_source='kiosk_device' then
    insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(b.organization_id,b.id,p_actor_user_id,'attendance.kiosk_marked','attendance_event',event_id,jsonb_build_object('employee_id',e.id,'event_type',p_event_type));
  end if;
  return jsonb_build_object('accepted',true,'attempt_id',attempt.id,'event_id',event_id,'distance_m',dist,'ip_passed',ip_ok,'gps_passed',gps_ok);
end $$;
revoke execute on function public.record_attendance_event(uuid,uuid,uuid,uuid,text,inet,numeric,numeric,numeric,boolean,text,boolean,text) from public,anon,authenticated;

create or replace function public.process_attendance(
  p_actor_user_id uuid,p_request_id uuid,p_branch_id uuid,p_event_type text,p_source_ip inet,
  p_latitude numeric,p_longitude numeric,p_gps_accuracy_m numeric,p_biometric_passed boolean,
  p_override_employee_id uuid default null,p_override_reason text default null
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare b public.branches%rowtype;e public.employees%rowtype;override_ok boolean:=false;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_user_id then raise exception 'actor mismatch';end if;
  select * into b from public.branches where id=p_branch_id and is_active;
  if b.id is null then raise exception 'branch not found';end if;
  if p_override_employee_id is null then
    select * into e from public.employees where user_id=p_actor_user_id and organization_id=b.organization_id and employment_status='active';
  else
    select * into e from public.employees where id=p_override_employee_id and organization_id=b.organization_id and employment_status='active';
    select exists(select 1 from public.branch_memberships bm where bm.branch_id=b.id and bm.user_id=p_actor_user_id and bm.is_active and bm.role='manager' and bm.can_override_attendance)
      or exists(select 1 from public.organization_memberships om where om.organization_id=b.organization_id and om.user_id=p_actor_user_id and om.is_active and om.role='owner') into override_ok;
    if not override_ok or length(trim(coalesce(p_override_reason,'')))<5 then raise exception 'override not permitted';end if;
  end if;
  if e.id is null then raise exception 'active employee not found';end if;
  return public.record_attendance_event(p_actor_user_id,p_request_id,p_branch_id,e.id,p_event_type,p_source_ip,p_latitude,p_longitude,
    p_gps_accuracy_m,p_biometric_passed,case when override_ok then 'manager_override' else 'employee_app' end,override_ok,p_override_reason);
end $$;

create or replace function public.process_attendance_with_face_proof(
  p_actor_user_id uuid,p_request_id uuid,p_branch_id uuid,p_event_type text,p_source_ip inet,p_latitude numeric,
  p_longitude numeric,p_gps_accuracy_m numeric,p_biometric_proof_id uuid,p_device_id text,
  p_override_employee_id uuid default null,p_override_reason text default null
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare b public.branches%rowtype;e public.employees%rowtype;proof public.face_verification_proofs%rowtype;
  existing public.attendance_attempts%rowtype;result jsonb;attempt_id uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_user_id then raise exception 'actor mismatch';end if;
  select * into existing from public.attendance_attempts where request_id=p_request_id;
  if existing.id is not null then return jsonb_build_object('accepted',existing.outcome='accepted','attempt_id',existing.id,'rejection_code',existing.rejection_code);end if;
  if p_override_employee_id is not null then
    result:=public.process_attendance(p_actor_user_id,p_request_id,p_branch_id,p_event_type,p_source_ip,p_latitude,p_longitude,p_gps_accuracy_m,false,p_override_employee_id,p_override_reason);
  else
    select * into b from public.branches where id=p_branch_id and is_active;
    select * into e from public.employees where user_id=p_actor_user_id and organization_id=b.organization_id and employment_status='active';
    if b.id is null or e.id is null then raise exception 'active employee or branch not found';end if;
    if b.requires_biometric then
      select * into proof from public.face_verification_proofs where id=p_biometric_proof_id and user_id=p_actor_user_id
        and employee_id=e.id and branch_id=b.id and device_id=p_device_id and liveness_passed and consumed_at is null and expires_at>now() for update;
    end if;
    if proof.id is not null then update public.face_verification_proofs set consumed_at=now() where id=proof.id;end if;
    result:=public.record_attendance_event(p_actor_user_id,p_request_id,p_branch_id,e.id,p_event_type,p_source_ip,p_latitude,p_longitude,
      p_gps_accuracy_m,not b.requires_biometric or proof.id is not null,'employee_app',false,null);
  end if;
  attempt_id:=nullif(result->>'attempt_id','')::uuid;
  update public.attendance_attempts set device_id=p_device_id,biometric_proof_id=proof.id where id=attempt_id;
  return result;
end $$;

create or replace function public.verify_employee_face_for_kiosk(
  p_actor_user_id uuid,p_employee_id uuid,p_branch_id uuid,p_device_id text,
  p_model_version text,p_descriptor jsonb,p_liveness_passed boolean
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare b public.branches%rowtype;e public.employees%rowtype;t public.employee_face_templates%rowtype;
  proof public.face_verification_proofs%rowtype;similarity numeric;candidate_norm numeric;template_norm numeric;dot_product numeric;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_user_id then raise exception 'actor mismatch';end if;
  if not coalesce(p_liveness_passed,false) then return jsonb_build_object('matched',false,'reason','liveness_required');end if;
  if p_model_version<>'adaface_ir18_v1' or jsonb_typeof(p_descriptor)<>'array' or jsonb_array_length(p_descriptor)<>512 then raise exception 'invalid face descriptor';end if;
  if exists(select 1 from jsonb_array_elements(p_descriptor) v(value) where jsonb_typeof(v.value)<>'number') then raise exception 'invalid face descriptor values';end if;
  select * into b from public.branches where id=p_branch_id and is_active;
  if b.id is null or not exists(select 1 from public.branch_kiosk_devices k where k.branch_id=b.id and k.device_id=p_device_id
    and k.registered_by=p_actor_user_id and k.is_active and k.revoked_at is null) then raise exception 'active kiosk registration required';end if;
  select * into e from public.employees where id=p_employee_id and organization_id=b.organization_id and employment_status='active';
  if e.id is null or not exists(select 1 from public.employee_branch_assignments a where a.employee_id=e.id and a.branch_id=b.id
    and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date)) then raise exception 'employee is not assigned to this kiosk branch';end if;
  select * into t from public.employee_face_templates where employee_id=e.id and revoked_at is null;
  if t.id is null then return jsonb_build_object('matched',false,'reason','face_not_enrolled');end if;
  if t.model_version<>p_model_version then return jsonb_build_object('matched',false,'reason','face_model_changed');end if;
  select sum(c.value::text::numeric*r.value::text::numeric),sqrt(sum(power(c.value::text::numeric,2))),sqrt(sum(power(r.value::text::numeric,2)))
  into dot_product,candidate_norm,template_norm
  from jsonb_array_elements(p_descriptor) with ordinality c(value,position)
  join jsonb_array_elements(t.descriptor) with ordinality r(value,position) using(position);
  if candidate_norm<0.95 or candidate_norm>1.05 or template_norm=0 then raise exception 'face descriptor is not normalized';end if;
  similarity:=dot_product/(candidate_norm*template_norm);
  if similarity<t.match_threshold then
    insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(e.organization_id,b.id,p_actor_user_id,'face.kiosk_verification_failed','employee',e.id,jsonb_build_object('similarity',round(similarity,5),'device_id',p_device_id));
    return jsonb_build_object('matched',false,'reason','face_not_matched');
  end if;
  insert into public.face_verification_proofs(organization_id,branch_id,employee_id,user_id,template_id,device_id,model_version,similarity,liveness_passed,expires_at)
  values(e.organization_id,b.id,e.id,p_actor_user_id,t.id,p_device_id,p_model_version,similarity,true,now()+interval '90 seconds') returning * into proof;
  return jsonb_build_object('matched',true,'proofId',proof.id,'expiresAt',proof.expires_at,'similarity',round(similarity,5));
end $$;

create or replace function public.process_kiosk_attendance(
  p_actor_user_id uuid,p_request_id uuid,p_branch_id uuid,p_employee_id uuid,p_event_type text,p_source_ip inet,
  p_latitude numeric,p_longitude numeric,p_gps_accuracy_m numeric,p_biometric_proof_id uuid,p_device_id text
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare b public.branches%rowtype;proof public.face_verification_proofs%rowtype;result jsonb;attempt_id uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_user_id then raise exception 'actor mismatch';end if;
  select * into b from public.branches where id=p_branch_id and is_active;
  if b.id is null or not exists(select 1 from public.branch_kiosk_devices k where k.branch_id=b.id and k.device_id=p_device_id
    and k.registered_by=p_actor_user_id and k.is_active and k.revoked_at is null) then raise exception 'active kiosk registration required';end if;
  select * into proof from public.face_verification_proofs where id=p_biometric_proof_id and user_id=p_actor_user_id
    and employee_id=p_employee_id and branch_id=b.id and device_id=p_device_id and liveness_passed and consumed_at is null and expires_at>now() for update;
  if proof.id is null then raise exception 'fresh kiosk face proof required';end if;
  update public.face_verification_proofs set consumed_at=now() where id=proof.id;
  result:=public.record_attendance_event(p_actor_user_id,p_request_id,p_branch_id,p_employee_id,p_event_type,p_source_ip,p_latitude,p_longitude,
    p_gps_accuracy_m,true,'kiosk_device',false,null);
  attempt_id:=nullif(result->>'attempt_id','')::uuid;
  update public.attendance_attempts set device_id=p_device_id,biometric_proof_id=proof.id where id=attempt_id;
  update public.branch_kiosk_devices set last_used_at=now() where branch_id=p_branch_id and device_id=p_device_id;
  return result;
end $$;

revoke execute on function public.verify_employee_face_for_kiosk(uuid,uuid,uuid,text,text,jsonb,boolean) from public,anon;
revoke execute on function public.process_kiosk_attendance(uuid,uuid,uuid,uuid,text,inet,numeric,numeric,numeric,uuid,text) from public,anon;
grant execute on function public.verify_employee_face_for_kiosk(uuid,uuid,uuid,text,text,jsonb,boolean) to authenticated;
grant execute on function public.process_kiosk_attendance(uuid,uuid,uuid,uuid,text,inet,numeric,numeric,numeric,uuid,text) to authenticated;

-- Consolidated multi-branch command center.
create or replace function public.mobile_multi_branch_summary(p_date date)
returns table(branch_id uuid,branch_code text,branch_name text,active_employees bigint,present bigint,absent bigint,on_leave bigint,
  pending_leaves bigint,pending_corrections bigint,scheduled_shifts bigint) language sql stable security definer
set search_path=pg_catalog,public,pg_temp
as $$
  select b.id,b.code,b.name,
    (select count(*) from public.employee_branch_assignments a join public.employees e on e.id=a.employee_id
      where a.branch_id=b.id and e.employment_status='active' and a.starts_on<=p_date and (a.ends_on is null or a.ends_on>=p_date)),
    (select count(*) from public.attendance_daily d where d.branch_id=b.id and d.work_date=p_date and d.status in ('present','partial')),
    (select count(*) from public.attendance_daily d where d.branch_id=b.id and d.work_date=p_date and d.status='absent'),
    (select count(*) from public.attendance_daily d where d.branch_id=b.id and d.work_date=p_date and d.status='leave'),
    (select count(*) from public.leave_requests l where l.branch_id=b.id and l.status='pending'),
    (select count(*) from public.attendance_correction_requests c where c.branch_id=b.id and c.status='pending'),
    (select count(*) from public.shift_roster_entries s where s.branch_id=b.id and s.work_date=p_date and s.status<>'cancelled')
  from public.branches b
  where b.is_active and (public.can_manage_branch(b.id) or public.has_org_role(b.organization_id,array['owner']))
  order by b.name;
$$;
revoke execute on function public.mobile_multi_branch_summary(date) from public,anon;
grant execute on function public.mobile_multi_branch_summary(date) to authenticated;

-- Immutable, server-generated payslip records and access history.
alter table public.payslip_documents
  add column version integer not null default 1 check(version>0),
  add column snapshot jsonb not null default '{}'::jsonb,
  add column content_sha256 text,
  add column content_type text not null default 'application/pdf',
  add column file_size_bytes bigint,
  add column payroll_locked_at timestamptz,
  add column payment_reference text;

create table public.payslip_access_events(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  payslip_document_id uuid not null references public.payslip_documents(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null check(action in ('view','download','share')),
  device_id text,
  created_at timestamptz not null default now()
);
alter table public.payslip_access_events enable row level security;
create policy payslip_access_read on public.payslip_access_events for select to authenticated
  using(public.is_employee_self(employee_id) or public.has_org_role(organization_id,array['owner']));
grant select on public.payslip_access_events to authenticated;
revoke insert,update,delete on public.payslip_access_events from anon,authenticated;
create index payslip_access_document_idx on public.payslip_access_events(payslip_document_id,created_at desc);
create index payslip_access_employee_idx on public.payslip_access_events(employee_id,created_at desc);
create index payslip_access_user_idx on public.payslip_access_events(user_id,created_at desc);

create or replace function public.prevent_payslip_document_mutation()
returns trigger language plpgsql
set search_path=pg_catalog,public,pg_temp
as $$ begin raise exception 'issued payslip documents are immutable';end $$;
drop trigger if exists payslip_documents_immutable on public.payslip_documents;
create trigger payslip_documents_immutable before update or delete on public.payslip_documents
for each row execute function public.prevent_payslip_document_mutation();

create or replace function public.record_payslip_access(p_document_id uuid,p_action text,p_device_id text default null)
returns boolean language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare document public.payslip_documents%rowtype;
begin
  if auth.uid() is null or p_action not in ('view','download','share') then raise exception 'invalid access event';end if;
  select * into document from public.payslip_documents where id=p_document_id;
  if document.id is null or not(public.is_employee_self(document.employee_id) or public.has_org_role(document.organization_id,array['owner'])) then raise exception 'not permitted';end if;
  insert into public.payslip_access_events(organization_id,payslip_document_id,employee_id,user_id,action,device_id)
  values(document.organization_id,document.id,document.employee_id,auth.uid(),p_action,nullif(trim(coalesce(p_device_id,'')),''));
  return true;
end $$;
revoke execute on function public.record_payslip_access(uuid,text,text) from public,anon;
grant execute on function public.record_payslip_access(uuid,text,text) to authenticated;

-- Owner-only bulk staff creation/update. Rows are validated and applied atomically.
create or replace function public.bulk_upsert_staff(p_branch_id uuid,p_rows jsonb)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare b public.branches%rowtype;item jsonb;e public.employees%rowtype;created integer:=0;updated integer:=0;assigned integer:=0;
  code text;name text;role_value text;join_date date;
begin
  select * into b from public.branches where id=p_branch_id and is_active;
  if b.id is null or not public.has_org_role(b.organization_id,array['owner']) then raise exception 'owner access required';end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>500 then raise exception 'provide 1 to 500 staff rows';end if;
  for item in select value from jsonb_array_elements(p_rows) loop
    code:=upper(trim(coalesce(item->>'employeeCode','')));name:=trim(coalesce(item->>'fullName',''));
    role_value:=case when lower(coalesce(item->>'role','staff'))='manager' then 'manager' else 'employee' end;
    join_date:=coalesce(nullif(item->>'joiningDate','')::date,current_date);
    if length(code)<2 or length(name)<2 then raise exception 'every row needs employeeCode and fullName';end if;
    select * into e from public.employees where organization_id=b.organization_id and employee_code=code for update;
    if e.id is null then
      insert into public.employees(organization_id,employee_code,full_name,phone,position,cnic,address,joining_date,employment_status,app_role,department,employment_type)
      values(b.organization_id,code,name,nullif(trim(coalesce(item->>'phone','')),''),nullif(trim(coalesce(item->>'position','')),''),
        nullif(trim(coalesce(item->>'cnic','')),''),nullif(trim(coalesce(item->>'address','')),''),join_date,'active',role_value,
        nullif(trim(coalesce(item->>'department','')),''),coalesce(nullif(item->>'employmentType',''),'full_time')) returning * into e;
      created:=created+1;
    else
      update public.employees set full_name=name,phone=coalesce(nullif(trim(item->>'phone'),''),phone),position=coalesce(nullif(trim(item->>'position'),''),position),
        department=coalesce(nullif(trim(item->>'department'),''),department),app_role=role_value where id=e.id returning * into e;
      updated:=updated+1;
    end if;
    insert into public.employee_branch_assignments(employee_id,branch_id,starts_on,is_primary)
    select e.id,b.id,join_date,true where not exists(select 1 from public.employee_branch_assignments a where a.employee_id=e.id and a.branch_id=b.id and (a.ends_on is null or a.ends_on>=current_date));
    if found then assigned:=assigned+1;end if;
  end loop;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,metadata)
  values(b.organization_id,b.id,auth.uid(),'employee.bulk_upserted','employee',jsonb_build_object('created',created,'updated',updated,'assigned',assigned));
  return jsonb_build_object('created',created,'updated',updated,'assigned',assigned);
end $$;
revoke execute on function public.bulk_upsert_staff(uuid,jsonb) from public,anon;
grant execute on function public.bulk_upsert_staff(uuid,jsonb) to authenticated;

-- Operational retention and health snapshots. This function is schedule/admin-only.
create table public.operational_health_snapshots(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  captured_on date not null,
  status text not null check(status in ('healthy','attention')),
  failed_pushes integer not null default 0,
  rejected_attendance integer not null default 0,
  failed_biometrics integer not null default 0,
  stale_kiosks integer not null default 0,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(organization_id,captured_on)
);
alter table public.operational_health_snapshots enable row level security;
create policy operational_health_owner_read on public.operational_health_snapshots for select to authenticated
  using(public.has_org_role(organization_id,array['owner']));
grant select on public.operational_health_snapshots to authenticated;
revoke insert,update,delete on public.operational_health_snapshots from anon,authenticated;

create or replace function public.run_production_maintenance(p_run_date date default current_date)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare org public.organizations%rowtype;pushes integer;attendance_failed integer;biometric_failed integer;kiosks integer;
  removed_challenges integer:=0;removed_proofs integer:=0;removed_notifications integer:=0;organizations_checked integer:=0;
begin
  delete from public.biometric_scan_challenges where expires_at<now()-interval '7 days';get diagnostics removed_challenges=row_count;
  delete from public.face_verification_proofs where expires_at<now()-interval '30 days';get diagnostics removed_proofs=row_count;
  delete from public.app_notifications where is_read and created_at<now()-interval '180 days';get diagnostics removed_notifications=row_count;
  for org in select * from public.organizations loop
    select count(*) into pushes from public.app_notifications where organization_id=org.id and push_sent_at is null and push_attempts>=3 and created_at>now()-interval '24 hours';
    select count(*) into attendance_failed from public.attendance_attempts where organization_id=org.id and outcome='rejected' and created_at>now()-interval '24 hours';
    select count(*) into biometric_failed from public.audit_events where organization_id=org.id and action like 'face.%failed' and created_at>now()-interval '24 hours';
    select count(*) into kiosks from public.branch_kiosk_devices where organization_id=org.id and is_active and coalesce(last_used_at,registered_at)<now()-interval '30 days';
    insert into public.operational_health_snapshots(organization_id,captured_on,status,failed_pushes,rejected_attendance,failed_biometrics,stale_kiosks,details)
    values(org.id,p_run_date,case when pushes+attendance_failed+biometric_failed>0 then 'attention' else 'healthy' end,pushes,attendance_failed,biometric_failed,kiosks,
      jsonb_build_object('retention','applied'))
    on conflict(organization_id,captured_on) do update set status=excluded.status,failed_pushes=excluded.failed_pushes,
      rejected_attendance=excluded.rejected_attendance,failed_biometrics=excluded.failed_biometrics,stale_kiosks=excluded.stale_kiosks,details=excluded.details;
    if pushes>0 then
      insert into public.app_notifications(organization_id,user_id,title,message,category,entity_type)
      select org.id,m.user_id,'Delivery needs attention',pushes||' notification deliveries could not be completed.','system','health'
      from public.organization_memberships m where m.organization_id=org.id and m.role='owner' and m.is_active
      and not exists(select 1 from public.app_notifications n where n.organization_id=org.id and n.user_id=m.user_id and n.title='Delivery needs attention' and n.created_at::date=p_run_date);
    end if;
    organizations_checked:=organizations_checked+1;
  end loop;
  return jsonb_build_object('organizations',organizations_checked,'removedChallenges',removed_challenges,'removedProofs',removed_proofs,'removedNotifications',removed_notifications);
end $$;
revoke execute on function public.run_production_maintenance(date) from public,anon,authenticated;

-- Advisor-backed missing foreign-key indexes and high-volume list indexes.
create index if not exists salary_ledger_payroll_item_idx on public.salary_ledger_transactions(payroll_item_id);
create index if not exists salary_ledger_rule_idx on public.salary_ledger_transactions(rule_id);
create index if not exists salary_ledger_reversal_idx on public.salary_ledger_transactions(reversal_of_id);
create index if not exists salary_food_created_by_idx on public.salary_food_items(created_by);
create index if not exists employee_branch_active_page_idx on public.employee_branch_assignments(branch_id,starts_on,ends_on,employee_id);
create index if not exists employees_org_name_page_idx on public.employees(organization_id,full_name,id);
create index if not exists leave_requests_branch_page_idx on public.leave_requests(branch_id,created_at desc,id desc);
create index if not exists payroll_runs_branch_page_idx on public.payroll_runs(branch_id,period_end desc,id desc);

-- Explicit function surface. Internal helpers stay unavailable to runtime roles.
revoke execute on function public.register_branch_kiosk(uuid,text,text) from public,anon;
revoke execute on function public.deactivate_branch_kiosk(uuid) from public,anon;
grant execute on function public.register_branch_kiosk(uuid,text,text) to authenticated;
grant execute on function public.deactivate_branch_kiosk(uuid) to authenticated;
