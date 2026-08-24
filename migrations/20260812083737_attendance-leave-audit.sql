create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.biometric_enrollments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  device_id text not null,
  biometric_type text not null check (biometric_type in ('face_id','touch_id','device_credential')),
  public_key text,
  enrolled_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (employee_id, device_id)
);

create table public.attendance_attempts (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  employee_id uuid references public.employees(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (event_type in ('check_in','check_out')),
  source_ip inet,
  latitude numeric(9,6),
  longitude numeric(9,6),
  gps_accuracy_m numeric(8,2),
  distance_m numeric(10,2),
  ip_passed boolean not null default false,
  gps_passed boolean not null default false,
  biometric_passed boolean not null default false,
  used_override boolean not null default false,
  outcome text not null check (outcome in ('accepted','rejected')),
  rejection_code text,
  created_at timestamptz not null default now()
);

create table public.attendance_events (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null unique references public.attendance_attempts(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  event_type text not null check (event_type in ('check_in','check_out')),
  occurred_at timestamptz not null default now(),
  local_work_date date not null,
  source text not null check (source in ('employee_app','manager_override','legacy_import')),
  created_at timestamptz not null default now()
);

create table public.attendance_daily (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete cascade,
  work_date date not null,
  first_check_in_at timestamptz,
  last_check_out_at timestamptz,
  worked_minutes integer not null default 0 check (worked_minutes >= 0),
  status text not null default 'present' check (status in ('present','absent','leave','partial')),
  updated_at timestamptz not null default now(),
  unique (employee_id, work_date)
);

create table public.attendance_overrides (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  manager_user_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check (event_type in ('check_in','check_out')),
  reason text not null check (length(trim(reason)) between 5 and 500),
  attendance_event_id uuid references public.attendance_events(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.leave_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  is_paid boolean not null default false,
  default_annual_days numeric(6,2) not null default 0 check (default_annual_days >= 0),
  requires_document boolean not null default false,
  requires_reason boolean not null default true,
  is_active boolean not null default true,
  effective_from date not null default current_date,
  effective_to date,
  created_at timestamptz not null default now(),
  unique (organization_id, code, effective_from),
  check (effective_to is null or effective_to >= effective_from)
);

create table public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete cascade,
  leave_type_id uuid not null references public.leave_types(id) on delete restrict,
  start_date date not null,
  end_date date not null,
  requested_days numeric(6,2) not null check (requested_days > 0),
  reason text,
  document_path text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  legacy_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table public.leave_balance_ledger (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  leave_type_id uuid not null references public.leave_types(id) on delete restrict,
  leave_request_id uuid references public.leave_requests(id) on delete restrict,
  entry_date date not null,
  days_delta numeric(6,2) not null check (days_delta <> 0),
  entry_type text not null check (entry_type in ('opening','accrual','approval','reversal','adjustment','expiry')),
  note text,
  actor_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index attendance_events_employee_date_idx on public.attendance_events(employee_id, local_work_date, occurred_at);
create index attendance_attempts_actor_idx on public.attendance_attempts(actor_user_id, created_at desc);
create index attendance_daily_branch_date_idx on public.attendance_daily(branch_id, work_date);
create index leave_requests_employee_idx on public.leave_requests(employee_id, created_at desc);
create index leave_requests_branch_status_idx on public.leave_requests(branch_id, status, start_date);
create index leave_ledger_balance_idx on public.leave_balance_ledger(employee_id, leave_type_id, entry_date);
create index audit_events_org_created_idx on public.audit_events(organization_id, created_at desc);

create trigger leave_requests_updated_at before update on public.leave_requests for each row execute function public.set_updated_at();
create trigger attendance_daily_updated_at before update on public.attendance_daily for each row execute function public.set_updated_at();

create or replace function public.distance_metres(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric)
returns numeric
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select case when lat1 is null or lon1 is null or lat2 is null or lon2 is null then null
    else 6371000 * 2 * asin(sqrt(
      power(sin(radians((lat2-lat1)::double precision)/2),2) +
      cos(radians(lat1::double precision))*cos(radians(lat2::double precision))*power(sin(radians((lon2-lon1)::double precision)/2),2)
    )) end;
$$;

create or replace function public.process_attendance(
  p_actor_user_id uuid,
  p_request_id uuid,
  p_branch_id uuid,
  p_event_type text,
  p_source_ip inet,
  p_latitude numeric,
  p_longitude numeric,
  p_gps_accuracy_m numeric,
  p_biometric_passed boolean,
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
  attempt public.attendance_attempts%rowtype;
  event_id uuid;
  ip_ok boolean := false;
  gps_ok boolean := false;
  access_ok boolean := false;
  override_ok boolean := false;
  dist numeric;
  work_day date;
  reject_code text;
begin
  if p_event_type not in ('check_in','check_out') then raise exception 'invalid event type'; end if;
  select * into attempt from public.attendance_attempts where request_id = p_request_id;
  if found then return jsonb_build_object('accepted', attempt.outcome='accepted', 'attempt_id', attempt.id, 'rejection_code', attempt.rejection_code); end if;
  select * into b from public.branches where id = p_branch_id and is_active;
  if not found then raise exception 'branch not found'; end if;
  if p_override_employee_id is null then
    select * into e from public.employees where user_id = p_actor_user_id and organization_id = b.organization_id and employment_status='active';
  else
    select * into e from public.employees where id = p_override_employee_id and organization_id = b.organization_id and employment_status='active';
    select exists(select 1 from public.branch_memberships bm where bm.branch_id=b.id and bm.user_id=p_actor_user_id and bm.is_active and bm.role in ('manager','branch_admin') and bm.can_override_attendance)
      or exists(select 1 from public.organization_memberships om where om.organization_id=b.organization_id and om.user_id=p_actor_user_id and om.is_active and om.role in ('owner','super_admin')) into override_ok;
    if not override_ok or p_override_reason is null or length(trim(p_override_reason)) < 5 then raise exception 'override not permitted'; end if;
  end if;
  if e.id is null then raise exception 'active employee not found'; end if;
  select exists(select 1 from public.employee_branch_assignments a where a.employee_id=e.id and a.branch_id=b.id and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date)) into access_ok;
  if not access_ok then raise exception 'employee is not assigned to this branch'; end if;
  select exists(select 1 from public.branch_ip_rules r where r.branch_id=b.id and r.is_active and (r.valid_from is null or r.valid_from<=now()) and (r.valid_until is null or r.valid_until>=now()) and p_source_ip <<= r.network) into ip_ok;
  dist := public.distance_metres(b.latitude,b.longitude,p_latitude,p_longitude);
  gps_ok := dist is not null and p_gps_accuracy_m is not null and p_gps_accuracy_m <= b.gps_accuracy_limit_m and dist <= b.geofence_radius_m;
  if not override_ok then
    if b.requires_biometric and not coalesce(p_biometric_passed,false) then reject_code := 'biometric_required';
    elsif b.attendance_verification_mode='IP_ONLY' and not ip_ok then reject_code := 'ip_not_allowed';
    elsif b.attendance_verification_mode='GPS_ONLY' and not gps_ok then reject_code := 'outside_geofence';
    elsif b.attendance_verification_mode='IP_OR_GPS' and not (ip_ok or gps_ok) then reject_code := 'location_not_verified';
    elsif b.attendance_verification_mode='IP_AND_GPS' and not (ip_ok and gps_ok) then reject_code := 'both_ip_and_gps_required'; end if;
  end if;
  insert into public.attendance_attempts(request_id,organization_id,branch_id,employee_id,actor_user_id,event_type,source_ip,latitude,longitude,gps_accuracy_m,distance_m,ip_passed,gps_passed,biometric_passed,used_override,outcome,rejection_code)
    values(p_request_id,b.organization_id,b.id,e.id,p_actor_user_id,p_event_type,p_source_ip,p_latitude,p_longitude,p_gps_accuracy_m,dist,ip_ok,gps_ok,coalesce(p_biometric_passed,false),override_ok,case when reject_code is null then 'accepted' else 'rejected' end,reject_code)
    returning * into attempt;
  if reject_code is not null then return jsonb_build_object('accepted',false,'attempt_id',attempt.id,'rejection_code',reject_code,'distance_m',dist,'ip_passed',ip_ok,'gps_passed',gps_ok); end if;
  work_day := (now() at time zone b.timezone)::date;
  insert into public.attendance_events(attempt_id,organization_id,branch_id,employee_id,event_type,local_work_date,source)
    values(attempt.id,b.organization_id,b.id,e.id,p_event_type,work_day,case when override_ok then 'manager_override' else 'employee_app' end) returning id into event_id;
  insert into public.attendance_daily(organization_id,branch_id,employee_id,work_date,first_check_in_at,last_check_out_at)
    values(b.organization_id,b.id,e.id,work_day,case when p_event_type='check_in' then now() end,case when p_event_type='check_out' then now() end)
    on conflict(employee_id,work_date) do update set first_check_in_at=coalesce(attendance_daily.first_check_in_at,excluded.first_check_in_at),last_check_out_at=coalesce(excluded.last_check_out_at,attendance_daily.last_check_out_at);
  if override_ok then
    insert into public.attendance_overrides(organization_id,branch_id,employee_id,manager_user_id,event_type,reason,attendance_event_id) values(b.organization_id,b.id,e.id,p_actor_user_id,p_event_type,trim(p_override_reason),event_id);
    insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,reason) values(b.organization_id,b.id,p_actor_user_id,'attendance.override','attendance_event',event_id,trim(p_override_reason));
  end if;
  return jsonb_build_object('accepted',true,'attempt_id',attempt.id,'event_id',event_id,'distance_m',dist,'ip_passed',ip_ok,'gps_passed',gps_ok);
end;
$$;

revoke all on function public.process_attendance(uuid,uuid,uuid,text,inet,numeric,numeric,numeric,boolean,uuid,text) from public, anon, authenticated;

create or replace function public.review_leave_request(p_request_id uuid, p_status text, p_note text default null)
returns public.leave_requests
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare r public.leave_requests%rowtype;
begin
  if p_status not in ('approved','rejected') then raise exception 'invalid review status'; end if;
  select * into r from public.leave_requests where id=p_request_id for update;
  if r.id is null or r.status <> 'pending' then raise exception 'request is not pending'; end if;
  if not public.can_manage_branch(r.branch_id) then raise exception 'not permitted'; end if;
  update public.leave_requests set status=p_status,reviewed_by=auth.uid(),reviewed_at=now(),review_note=p_note where id=r.id returning * into r;
  if p_status='approved' then
    insert into public.leave_balance_ledger(organization_id,employee_id,leave_type_id,leave_request_id,entry_date,days_delta,entry_type,note,actor_user_id)
      values(r.organization_id,r.employee_id,r.leave_type_id,r.id,current_date,-r.requested_days,'approval',p_note,auth.uid());
  end if;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,reason) values(r.organization_id,r.branch_id,auth.uid(),'leave.'||p_status,'leave_request',r.id,p_note);
  return r;
end;
$$;

alter table public.audit_events enable row level security;
alter table public.biometric_enrollments enable row level security;
alter table public.attendance_attempts enable row level security;
alter table public.attendance_events enable row level security;
alter table public.attendance_daily enable row level security;
alter table public.attendance_overrides enable row level security;
alter table public.leave_types enable row level security;
alter table public.leave_requests enable row level security;
alter table public.leave_balance_ledger enable row level security;

create policy audit_select on public.audit_events for select to authenticated using (public.has_org_role(organization_id,array['owner','super_admin']));
create policy biometric_select on public.biometric_enrollments for select to authenticated using (public.is_employee_self(employee_id) or exists(select 1 from public.employee_branch_assignments a where a.employee_id=biometric_enrollments.employee_id and public.can_manage_branch(a.branch_id)));
create policy biometric_manage_self on public.biometric_enrollments for all to authenticated using (public.is_employee_self(employee_id)) with check (public.is_employee_self(employee_id));
create policy attempts_select on public.attendance_attempts for select to authenticated using (actor_user_id=auth.uid() or public.is_employee_self(employee_id) or public.can_manage_branch(branch_id));
create policy events_select on public.attendance_events for select to authenticated using (public.is_employee_self(employee_id) or public.is_branch_member(branch_id));
create policy daily_select on public.attendance_daily for select to authenticated using (public.is_employee_self(employee_id) or public.is_branch_member(branch_id));
create policy overrides_select on public.attendance_overrides for select to authenticated using (public.is_employee_self(employee_id) or public.can_manage_branch(branch_id) or public.has_org_role(organization_id,array['owner','super_admin']));
create policy leave_types_select on public.leave_types for select to authenticated using (public.is_org_member(organization_id));
create policy leave_types_manage on public.leave_types for all to authenticated using (public.has_org_role(organization_id,array['owner','super_admin','hr_admin'])) with check (public.has_org_role(organization_id,array['owner','super_admin','hr_admin']));
create policy leave_requests_select on public.leave_requests for select to authenticated using (public.is_employee_self(employee_id) or public.can_manage_branch(branch_id) or public.has_org_role(organization_id,array['owner','super_admin','hr_admin','payroll_admin']));
create policy leave_requests_insert_self on public.leave_requests for insert to authenticated with check (public.is_employee_self(employee_id) and status='pending' and exists(select 1 from public.employee_branch_assignments a where a.employee_id=leave_requests.employee_id and a.branch_id=leave_requests.branch_id and a.starts_on<=start_date and (a.ends_on is null or a.ends_on>=end_date)));
create policy leave_requests_cancel_self on public.leave_requests for update to authenticated using (public.is_employee_self(employee_id) and status='pending') with check (public.is_employee_self(employee_id) and status in ('pending','cancelled'));
create policy leave_ledger_select on public.leave_balance_ledger for select to authenticated using (public.is_employee_self(employee_id) or public.has_org_role(organization_id,array['owner','super_admin','hr_admin','payroll_admin']) or exists(select 1 from public.employee_branch_assignments a where a.employee_id=leave_balance_ledger.employee_id and public.can_manage_branch(a.branch_id)));

grant select on public.audit_events,public.attendance_attempts,public.attendance_events,public.attendance_daily,public.attendance_overrides,public.leave_balance_ledger to authenticated;
grant select,insert,update,delete on public.biometric_enrollments,public.leave_types to authenticated;
grant select,insert,update on public.leave_requests to authenticated;
grant execute on function public.review_leave_request(uuid,text,text) to authenticated;
revoke update,delete on public.audit_events,public.attendance_attempts,public.attendance_events,public.attendance_overrides,public.leave_balance_ledger from authenticated;
