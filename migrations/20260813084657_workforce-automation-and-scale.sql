-- Workforce automation, trustworthy offline capture, historical reporting and scale hardening.

alter table public.leave_balance_ledger add column source_key text;
create unique index leave_balance_source_key_idx
  on public.leave_balance_ledger(employee_id,leave_type_id,source_key)
  where source_key is not null;

alter table public.employees
  add column department text,
  add column reporting_manager_id uuid references public.employees(id) on delete set null,
  add column employment_type text not null default 'full_time'
    check (employment_type in ('full_time','part_time','contract','temporary','intern')),
  add column probation_end_date date,
  add column emergency_contact_name text,
  add column emergency_contact_phone text,
  add column date_of_birth date;

alter table public.shift_roster_entries
  add column is_published boolean not null default false,
  add column published_at timestamptz,
  add column published_by uuid references auth.users(id) on delete set null;

create table public.employee_availability (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  available_from time,
  available_until time,
  is_available boolean not null default true,
  note text,
  updated_at timestamptz not null default now(),
  unique(employee_id,weekday),
  check (not is_available or (available_from is not null and available_until is not null and available_from<>available_until))
);

create table public.employee_lifecycle_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  phase text not null check (phase in ('onboarding','probation','offboarding')),
  title text not null check (length(trim(title)) between 2 and 120),
  due_on date,
  status text not null default 'pending' check (status in ('pending','completed','waived')),
  completed_at timestamptz,
  completed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.employee_assets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  asset_type text not null,
  label text not null,
  identifier text,
  issued_on date not null default current_date,
  returned_on date,
  condition_note text,
  created_at timestamptz not null default now(),
  check (returned_on is null or returned_on>=issued_on)
);

create table public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  push_enabled boolean not null default true,
  attendance_enabled boolean not null default true,
  shifts_enabled boolean not null default true,
  leave_enabled boolean not null default true,
  payroll_enabled boolean not null default true,
  documents_enabled boolean not null default true,
  quiet_start time,
  quiet_end time,
  updated_at timestamptz not null default now()
);

create table public.trusted_devices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (length(device_id) between 8 and 200),
  public_key text not null check (length(public_key) between 80 and 500),
  key_algorithm text not null default 'p256-secure-enclave',
  device_name text,
  is_active boolean not null default true,
  enrolled_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique(user_id,device_id)
);

create table public.offline_attendance_submissions (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  device_id text not null,
  event_type text not null check (event_type in ('check_in','check_out')),
  captured_at timestamptz not null,
  synced_at timestamptz not null default now(),
  latitude numeric not null,
  longitude numeric not null,
  gps_accuracy_m numeric not null,
  distance_m numeric not null,
  challenge_action text not null,
  signature text not null,
  biometric_similarity numeric(6,5) not null,
  attendance_event_id uuid references public.attendance_events(id) on delete set null,
  unique(actor_user_id,device_id,captured_at,event_type)
);

alter table public.attendance_events drop constraint attendance_events_source_check;
alter table public.attendance_events add constraint attendance_events_source_check
  check (source in ('employee_app','manager_override','legacy_import','offline_verified'));

create index employees_reporting_manager_idx on public.employees(reporting_manager_id);
create index availability_org_branch_idx on public.employee_availability(organization_id,branch_id,weekday);
create index lifecycle_employee_status_idx on public.employee_lifecycle_tasks(employee_id,status,due_on);
create index lifecycle_org_idx on public.employee_lifecycle_tasks(organization_id);
create index lifecycle_completed_by_idx on public.employee_lifecycle_tasks(completed_by) where completed_by is not null;
create index assets_employee_returned_idx on public.employee_assets(employee_id,returned_on);
create index assets_org_idx on public.employee_assets(organization_id);
create index notification_preferences_org_idx on public.notification_preferences(organization_id);
create index trusted_devices_org_user_idx on public.trusted_devices(organization_id,user_id,is_active);
create index offline_attendance_branch_captured_idx on public.offline_attendance_submissions(branch_id,captured_at desc);
create index offline_attendance_employee_idx on public.offline_attendance_submissions(employee_id,captured_at desc);
create index offline_attendance_event_idx on public.offline_attendance_submissions(attendance_event_id) where attendance_event_id is not null;
create index shift_roster_published_idx on public.shift_roster_entries(branch_id,work_date,is_published) where status<>'cancelled';
create index shift_roster_created_by_idx on public.shift_roster_entries(created_by) where created_by is not null;
create index shift_roster_published_by_idx on public.shift_roster_entries(published_by) where published_by is not null;

-- Remaining advisor findings on operational foreign keys.
create index shift_swap_org_idx on public.shift_swap_requests(organization_id);
create index shift_swap_roster_idx on public.shift_swap_requests(roster_entry_id);
create index shift_swap_reviewed_by_idx on public.shift_swap_requests(reviewed_by) where reviewed_by is not null;
create index payroll_loans_created_by_idx on public.payroll_loans(created_by) where created_by is not null;
create index leave_blackouts_branch_idx on public.leave_blackout_periods(branch_id) where branch_id is not null;
create index leave_blackouts_created_by_idx on public.leave_blackout_periods(created_by) where created_by is not null;
create index leave_steps_approver_idx on public.leave_approval_steps(approver_user_id) where approver_user_id is not null;
create index reimbursements_payroll_item_idx on public.payroll_reimbursements(payroll_item_id) where payroll_item_id is not null;
create index reimbursements_reviewed_by_idx on public.payroll_reimbursements(reviewed_by) where reviewed_by is not null;
create index holidays_branch_idx on public.public_holidays(branch_id) where branch_id is not null;
create index corrections_reviewed_by_idx on public.attendance_correction_requests(reviewed_by) where reviewed_by is not null;
create index corrections_org_idx on public.attendance_correction_requests(organization_id);
create index employee_documents_uploaded_by_idx on public.employee_documents(uploaded_by) where uploaded_by is not null;
create index loan_installments_payroll_item_idx on public.payroll_loan_installments(payroll_item_id);
create index biometric_challenges_branch_idx on public.biometric_scan_challenges(branch_id);

create trigger availability_updated_at before update on public.employee_availability
for each row execute function public.set_updated_at();
create trigger notification_preferences_updated_at before update on public.notification_preferences
for each row execute function public.set_updated_at();

alter table public.employee_availability enable row level security;
alter table public.employee_lifecycle_tasks enable row level security;
alter table public.employee_assets enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.trusted_devices enable row level security;
alter table public.offline_attendance_submissions enable row level security;

create policy availability_read on public.employee_availability for select to authenticated
  using (public.is_employee_self(employee_id) or public.can_manage_branch(branch_id));
create policy availability_write on public.employee_availability for all to authenticated
  using (public.is_employee_self(employee_id) or public.can_manage_branch(branch_id))
  with check (public.is_employee_self(employee_id) or public.can_manage_branch(branch_id));
create policy lifecycle_read on public.employee_lifecycle_tasks for select to authenticated
  using (public.is_employee_self(employee_id) or public.has_org_role(organization_id,array['owner','super_admin','hr_admin']));
create policy lifecycle_manage on public.employee_lifecycle_tasks for all to authenticated
  using (public.has_org_role(organization_id,array['owner','super_admin','hr_admin']))
  with check (public.has_org_role(organization_id,array['owner','super_admin','hr_admin']));
create policy assets_read on public.employee_assets for select to authenticated
  using (public.is_employee_self(employee_id) or public.has_org_role(organization_id,array['owner','super_admin','hr_admin']));
create policy assets_manage on public.employee_assets for all to authenticated
  using (public.has_org_role(organization_id,array['owner','super_admin','hr_admin']))
  with check (public.has_org_role(organization_id,array['owner','super_admin','hr_admin']));
create policy preferences_own on public.notification_preferences for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()) and public.is_org_member(organization_id));
create policy trusted_devices_own_read on public.trusted_devices for select to authenticated
  using (user_id=(select auth.uid()) or public.has_org_role(organization_id,array['owner','super_admin']));
create policy trusted_devices_own_write on public.trusted_devices for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()) and public.is_org_member(organization_id));
create policy offline_attendance_read on public.offline_attendance_submissions for select to authenticated
  using (actor_user_id=(select auth.uid()) or public.can_manage_branch(branch_id));

drop policy if exists push_tokens_own on public.mobile_push_tokens;
create policy push_tokens_own on public.mobile_push_tokens for select to authenticated
  using (user_id=(select auth.uid()));

grant select,insert,update on public.employee_availability,public.employee_lifecycle_tasks,public.employee_assets,public.notification_preferences,public.trusted_devices to authenticated;
grant select on public.offline_attendance_submissions to authenticated;
revoke insert,update,delete on public.offline_attendance_submissions from authenticated;

create or replace function public.register_trusted_device(p_device_id text,p_public_key text,p_device_name text default null)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare org uuid;
begin
  if length(trim(coalesce(p_device_id,'')))<8 or length(trim(coalesce(p_public_key,'')))<80 then raise exception 'invalid device identity'; end if;
  select organization_id into org from public.organization_memberships where user_id=auth.uid() and is_active order by created_at limit 1;
  if org is null then raise exception 'organization membership required'; end if;
  insert into public.trusted_devices(organization_id,user_id,device_id,public_key,device_name)
  values(org,auth.uid(),trim(p_device_id),trim(p_public_key),nullif(trim(coalesce(p_device_name,'')),''))
  on conflict(user_id,device_id) do update set public_key=excluded.public_key,device_name=excluded.device_name,is_active=true,revoked_at=null,last_seen_at=now();
  return true;
end $$;

create or replace function public.trusted_device_public_key(p_actor_user_id uuid,p_device_id text)
returns text language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select public_key from public.trusted_devices where user_id=p_actor_user_id and device_id=p_device_id and is_active and revoked_at is null;
$$;

create or replace function public.process_offline_attendance(
  p_actor_user_id uuid,p_request_id uuid,p_branch_id uuid,p_event_type text,p_captured_at timestamptz,
  p_latitude numeric,p_longitude numeric,p_gps_accuracy_m numeric,p_device_id text,
  p_biometric_proof_id uuid,p_challenge_action text,p_signature text
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare b public.branches%rowtype;e public.employees%rowtype;proof public.face_verification_proofs%rowtype;
attempt public.attendance_attempts%rowtype;event_id uuid;dist numeric;work_day date;
begin
  select * into attempt from public.attendance_attempts where request_id=p_request_id;
  if attempt.id is not null then return jsonb_build_object('accepted',attempt.outcome='accepted','attemptId',attempt.id,'rejectionCode',attempt.rejection_code);end if;
  if p_event_type not in ('check_in','check_out') or p_captured_at>now()+interval '5 minutes' or p_captured_at<now()-interval '12 hours' then raise exception 'offline capture expired';end if;
  select * into b from public.branches where id=p_branch_id and is_active;
  select * into e from public.employees where user_id=p_actor_user_id and organization_id=b.organization_id and employment_status='active';
  if b.id is null or e.id is null then raise exception 'active employee or branch not found';end if;
  if not exists(select 1 from public.trusted_devices where user_id=p_actor_user_id and device_id=p_device_id and is_active and revoked_at is null) then raise exception 'device is not trusted';end if;
  work_day:=(p_captured_at at time zone b.timezone)::date;
  if not exists(select 1 from public.employee_branch_assignments a where a.employee_id=e.id and a.branch_id=b.id and a.starts_on<=work_day and (a.ends_on is null or a.ends_on>=work_day)) then raise exception 'employee is not assigned to this branch';end if;
  dist:=public.distance_metres(b.latitude,b.longitude,p_latitude,p_longitude);
  if dist is null or p_gps_accuracy_m is null or p_gps_accuracy_m>b.gps_accuracy_limit_m or dist>b.geofence_radius_m then raise exception 'offline location could not be verified';end if;
  select * into proof from public.face_verification_proofs where id=p_biometric_proof_id and user_id=p_actor_user_id and employee_id=e.id and branch_id=b.id and device_id=p_device_id and liveness_passed and consumed_at is null and expires_at>now() for update;
  if b.requires_biometric and proof.id is null then raise exception 'offline biometric proof is required';end if;
  if proof.id is not null then update public.face_verification_proofs set consumed_at=now() where id=proof.id;end if;
  insert into public.attendance_attempts(request_id,organization_id,branch_id,employee_id,actor_user_id,event_type,latitude,longitude,gps_accuracy_m,distance_m,ip_passed,gps_passed,biometric_passed,used_override,outcome,created_at,device_id,biometric_proof_id)
  values(p_request_id,b.organization_id,b.id,e.id,p_actor_user_id,p_event_type,p_latitude,p_longitude,p_gps_accuracy_m,dist,false,true,not b.requires_biometric or proof.id is not null,false,'accepted',p_captured_at,p_device_id,proof.id) returning * into attempt;
  insert into public.attendance_events(attempt_id,organization_id,branch_id,employee_id,event_type,occurred_at,local_work_date,source)
  values(attempt.id,b.organization_id,b.id,e.id,p_event_type,p_captured_at,work_day,'offline_verified') returning id into event_id;
  insert into public.attendance_daily(organization_id,branch_id,employee_id,work_date,first_check_in_at,last_check_out_at)
  values(b.organization_id,b.id,e.id,work_day,case when p_event_type='check_in' then p_captured_at end,case when p_event_type='check_out' then p_captured_at end)
  on conflict(employee_id,work_date) do update set first_check_in_at=case when excluded.first_check_in_at is null then attendance_daily.first_check_in_at else least(coalesce(attendance_daily.first_check_in_at,excluded.first_check_in_at),excluded.first_check_in_at) end,last_check_out_at=case when excluded.last_check_out_at is null then attendance_daily.last_check_out_at else greatest(coalesce(attendance_daily.last_check_out_at,excluded.last_check_out_at),excluded.last_check_out_at) end;
  insert into public.offline_attendance_submissions(id,organization_id,branch_id,employee_id,actor_user_id,device_id,event_type,captured_at,latitude,longitude,gps_accuracy_m,distance_m,challenge_action,signature,biometric_similarity,attendance_event_id)
  values(p_request_id,b.organization_id,b.id,e.id,p_actor_user_id,p_device_id,p_event_type,p_captured_at,p_latitude,p_longitude,p_gps_accuracy_m,dist,p_challenge_action,p_signature,coalesce(proof.similarity,1),event_id);
  update public.trusted_devices set last_seen_at=now() where user_id=p_actor_user_id and device_id=p_device_id;
  return jsonb_build_object('accepted',true,'attemptId',attempt.id,'eventId',event_id,'distanceM',dist,'gpsPassed',true,'syncedOffline',true);
end $$;

create or replace function public.bulk_copy_roster(p_branch_id uuid,p_source_start date,p_target_start date)
returns integer language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare copied integer;
begin
  if not public.can_manage_branch(p_branch_id) then raise exception 'not permitted';end if;
  insert into public.shift_roster_entries(organization_id,branch_id,employee_id,work_date,starts_at,ends_at,break_minutes,status,notes,created_by,is_published)
  select organization_id,branch_id,employee_id,p_target_start+(work_date-p_source_start),starts_at,ends_at,break_minutes,'scheduled',notes,auth.uid(),false
  from public.shift_roster_entries where branch_id=p_branch_id and work_date between p_source_start and p_source_start+6 and status<>'cancelled'
  on conflict(employee_id,work_date) do update set starts_at=excluded.starts_at,ends_at=excluded.ends_at,break_minutes=excluded.break_minutes,status='scheduled',notes=excluded.notes,is_published=false,published_at=null,published_by=null;
  get diagnostics copied=row_count;return copied;
end $$;

create or replace function public.publish_roster(p_branch_id uuid,p_week_start date)
returns integer language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare published integer;
begin
  if not public.can_manage_branch(p_branch_id) then raise exception 'not permitted';end if;
  update public.shift_roster_entries set is_published=true,published_at=now(),published_by=auth.uid(),status=case when status='scheduled' then 'confirmed' else status end
  where branch_id=p_branch_id and work_date between p_week_start and p_week_start+6 and status<>'cancelled';
  get diagnostics published=row_count;return published;
end $$;

create or replace function public.mobile_workforce_report(p_branch_id uuid,p_from date,p_to date,p_kind text default 'all')
returns table(report_type text,record_id uuid,employee_id uuid,employee_name text,employee_code text,record_date date,status text,amount_minor bigint,details text)
language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select * from (
  select 'attendance'::text report_type,a.id record_id,a.employee_id,e.full_name employee_name,e.employee_code,a.work_date record_date,a.status,null::bigint amount_minor,
    concat_ws(' · ',case when a.first_check_in_at is not null then 'In '||to_char(a.first_check_in_at,'HH24:MI') end,case when a.last_check_out_at is not null then 'Out '||to_char(a.last_check_out_at,'HH24:MI') end,'Worked '||a.worked_minutes||' min')
  from public.attendance_daily a join public.employees e on e.id=a.employee_id
  where p_kind in ('all','attendance') and a.branch_id=p_branch_id and a.work_date between p_from and p_to
    and (public.can_manage_branch(p_branch_id) or public.is_employee_self(a.employee_id))
  union all
  select 'leave',l.id,l.employee_id,e.full_name,e.employee_code,l.start_date,l.status,null::bigint,
    coalesce(l.requested_days,0)||' day(s) · '||l.start_date||' to '||l.end_date
  from public.leave_requests l join public.employees e on e.id=l.employee_id
  where p_kind in ('all','leave') and l.branch_id=p_branch_id and l.start_date<=p_to and l.end_date>=p_from
    and (public.can_manage_branch(p_branch_id) or public.is_employee_self(l.employee_id))
  union all
  select 'payroll',pi.id,pi.employee_id,e.full_name,e.employee_code,r.period_end,pi.status,pi.net_minor,r.title
  from public.payroll_items pi join public.payroll_runs r on r.id=pi.payroll_run_id join public.employees e on e.id=pi.employee_id
  where p_kind in ('all','payroll') and (r.branch_id=p_branch_id or (r.branch_id is null and e.organization_id=r.organization_id)) and r.period_start<=p_to and r.period_end>=p_from
    and (public.is_employee_self(pi.employee_id) or public.can_manage_payroll(r.organization_id))
  ) report_rows order by report_rows.record_date desc,report_rows.employee_name limit 5000;
$$;

create or replace function public.mark_all_notifications_read()
returns integer language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare changed integer;begin update public.app_notifications set is_read=true where user_id=auth.uid() and not is_read;get diagnostics changed=row_count;return changed;end $$;

create or replace function public.run_leave_accruals(p_run_date date default current_date)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r record;period_date date;anniversary date;grant_days numeric;added integer:=0;expired integer:=0;prior_balance numeric;year_start date;yr integer;
begin
  for r in select e.id employee_id,e.organization_id,e.joining_date,lt.id leave_type_id,lt.default_annual_days,lt.accrual_method,lt.carry_forward_days,lt.effective_from
    from public.employees e join public.leave_types lt on lt.organization_id=e.organization_id
    where e.employment_status='active' and e.joining_date<=p_run_date and lt.is_active and lt.default_annual_days>0 and lt.effective_from<=p_run_date and (lt.effective_to is null or lt.effective_to>=e.joining_date)
  loop
    for yr in greatest(extract(year from r.joining_date)::int,extract(year from r.effective_from)::int)..extract(year from p_run_date)::int loop
      year_start:=make_date(yr,1,1);
      if yr>extract(year from greatest(r.joining_date,r.effective_from))::int then
        select coalesce(sum(days_delta),0) into prior_balance from public.leave_balance_ledger where employee_id=r.employee_id and leave_type_id=r.leave_type_id and entry_date<year_start;
        if prior_balance>r.carry_forward_days then
          insert into public.leave_balance_ledger(organization_id,employee_id,leave_type_id,entry_date,days_delta,entry_type,note,source_key)
          values(r.organization_id,r.employee_id,r.leave_type_id,year_start,-(prior_balance-r.carry_forward_days),'expiry','Automatic annual carry-forward cap','expiry:'||yr)
          on conflict(employee_id,leave_type_id,source_key) where source_key is not null do nothing;
          if found then expired:=expired+1;end if;
        end if;
      end if;
    end loop;
    if r.accrual_method='monthly' then
      for period_date in select gs::date from generate_series(date_trunc('month',greatest(r.joining_date,r.effective_from))::date,date_trunc('month',p_run_date)::date,interval '1 month') gs loop
        grant_days:=r.default_annual_days/12;
        if date_trunc('month',greatest(r.joining_date,r.effective_from))::date=period_date then
          grant_days:=grant_days*((period_date+interval '1 month')::date-greatest(r.joining_date,r.effective_from))::numeric/((period_date+interval '1 month')::date-period_date);
        end if;
        insert into public.leave_balance_ledger(organization_id,employee_id,leave_type_id,entry_date,days_delta,entry_type,note,source_key)
        values(r.organization_id,r.employee_id,r.leave_type_id,period_date,round(grant_days,2),'accrual','Automatic monthly accrual','monthly:'||to_char(period_date,'YYYY-MM'))
        on conflict(employee_id,leave_type_id,source_key) where source_key is not null do nothing;if found then added:=added+1;end if;
      end loop;
    elsif r.accrual_method='joining_anniversary' then
      for yr in extract(year from greatest(r.joining_date,r.effective_from))::int..extract(year from p_run_date)::int loop
        anniversary:=make_date(yr,extract(month from r.joining_date)::int,least(extract(day from r.joining_date)::int,extract(day from (date_trunc('month',make_date(yr,extract(month from r.joining_date)::int,1))+interval '1 month-1 day'))::int));
        if anniversary>=greatest(r.joining_date,r.effective_from) and anniversary<=p_run_date then
          insert into public.leave_balance_ledger(organization_id,employee_id,leave_type_id,entry_date,days_delta,entry_type,note,source_key)
          values(r.organization_id,r.employee_id,r.leave_type_id,anniversary,r.default_annual_days,'accrual','Automatic joining-anniversary accrual','anniversary:'||yr)
          on conflict(employee_id,leave_type_id,source_key) where source_key is not null do nothing;if found then added:=added+1;end if;
        end if;
      end loop;
    else
      for yr in extract(year from greatest(r.joining_date,r.effective_from))::int..extract(year from p_run_date)::int loop
        period_date:=greatest(make_date(yr,1,1),r.joining_date,r.effective_from);
        if period_date<=p_run_date then
          grant_days:=r.default_annual_days;
          if period_date>make_date(yr,1,1) then grant_days:=grant_days*(make_date(yr+1,1,1)-period_date)::numeric/(make_date(yr+1,1,1)-make_date(yr,1,1));end if;
          insert into public.leave_balance_ledger(organization_id,employee_id,leave_type_id,entry_date,days_delta,entry_type,note,source_key)
          values(r.organization_id,r.employee_id,r.leave_type_id,period_date,round(grant_days,2),'accrual','Automatic annual accrual','annual:'||yr)
          on conflict(employee_id,leave_type_id,source_key) where source_key is not null do nothing;if found then added:=added+1;end if;
        end if;
      end loop;
    end if;
  end loop;
  return jsonb_build_object('runDate',p_run_date,'accrualsAdded',added,'expiriesAdded',expired);
end $$;

create or replace function public.enqueue_operational_reminders(p_run_date date default current_date)
returns integer language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare inserted_count integer:=0;changed integer;
begin
  insert into public.app_notifications(organization_id,user_id,title,message,category,entity_type,entity_id)
  select d.organization_id,e.user_id,'Document expires soon',d.title||' expires on '||d.expires_on,'documents','employee_document',d.id
  from public.employee_documents d join public.employees e on e.id=d.employee_id
  where e.user_id is not null and d.expires_on in (p_run_date+7,p_run_date+30)
    and not exists(select 1 from public.app_notifications n where n.user_id=e.user_id and n.category='documents' and n.entity_id=d.id and n.created_at::date=p_run_date);
  get diagnostics changed=row_count;inserted_count:=inserted_count+changed;
  insert into public.app_notifications(organization_id,user_id,title,message,category,entity_type,entity_id)
  select s.organization_id,e.user_id,'Shift tomorrow',to_char(s.starts_at,'HH24:MI')||' at '||b.name,'shift','shift_roster_entry',s.id
  from public.shift_roster_entries s join public.employees e on e.id=s.employee_id join public.branches b on b.id=s.branch_id
  where e.user_id is not null and s.work_date=p_run_date+1 and s.is_published and s.status<>'cancelled'
    and not exists(select 1 from public.app_notifications n where n.user_id=e.user_id and n.category='shift' and n.entity_id=s.id);
  get diagnostics changed=row_count;inserted_count:=inserted_count+changed;
  return inserted_count;
end $$;

create or replace function public.claim_push_notification_batch(p_limit integer default 50)
returns table(notification_id uuid,user_id uuid,title text,message text,category text,token text,environment text)
language sql security definer set search_path=pg_catalog,public,pg_temp as $$
  with candidates as (
    select n.id from public.app_notifications n
    left join public.notification_preferences p on p.user_id=n.user_id
    where n.push_sent_at is null and n.push_attempts<10 and n.created_at>now()-interval '3 days'
      and coalesce(p.push_enabled,true)
      and case
        when n.category like 'attendance%' then coalesce(p.attendance_enabled,true)
        when n.category in ('shift','schedule','shift_swap') then coalesce(p.shifts_enabled,true)
        when n.category like 'leave%' then coalesce(p.leave_enabled,true)
        when n.category like 'payroll%' then coalesce(p.payroll_enabled,true)
        when n.category='documents' then coalesce(p.documents_enabled,true)
        else true end
      and (p.quiet_start is null or p.quiet_end is null or not case when p.quiet_start<=p.quiet_end then localtime>=p.quiet_start and localtime<p.quiet_end else localtime>=p.quiet_start or localtime<p.quiet_end end)
    order by n.created_at limit least(greatest(p_limit,1),100) for update of n skip locked
  ),claimed as(update public.app_notifications n set push_attempts=push_attempts+1 from candidates c where n.id=c.id returning n.*)
  select c.id,c.user_id,c.title,c.message,c.category,t.token,t.environment from claimed c join public.mobile_push_tokens t on t.user_id=c.user_id and t.is_active;
$$;

create or replace function public.publish_employee_hub_change()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare org uuid;branch uuid;record_id uuid;status_value text;payload jsonb;
begin payload:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;org:=nullif(payload->>'organization_id','')::uuid;branch:=nullif(payload->>'branch_id','')::uuid;record_id:=nullif(payload->>'id','')::uuid;status_value:=coalesce(payload->>'status','updated');perform realtime.publish('employee-hub:'||org::text,'data_changed',jsonb_build_object('table',tg_table_name,'id',record_id,'branchId',branch,'status',status_value));if tg_op='DELETE' then return old;else return new;end if;end $$;

create trigger attendance_daily_realtime after insert or update or delete on public.attendance_daily for each row execute function public.publish_employee_hub_change();
create trigger employee_documents_realtime after insert or update or delete on public.employee_documents for each row execute function public.publish_employee_hub_change();
create trigger shift_swaps_realtime after insert or update or delete on public.shift_swap_requests for each row execute function public.publish_employee_hub_change();
create trigger payroll_items_realtime after insert or update or delete on public.payroll_items for each row execute function public.publish_employee_hub_change();

grant execute on function public.register_trusted_device(text,text,text),public.bulk_copy_roster(uuid,date,date),public.publish_roster(uuid,date),public.mobile_workforce_report(uuid,date,date,text),public.mark_all_notifications_read() to authenticated;
revoke all on function public.trusted_device_public_key(uuid,text),public.process_offline_attendance(uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,uuid,text,text),public.run_leave_accruals(date),public.enqueue_operational_reminders(date),public.claim_push_notification_batch(integer) from public,anon,authenticated;
