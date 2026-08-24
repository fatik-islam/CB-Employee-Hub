-- Operational depth and mobile-performance upgrade for CB Employee Hub.

create table public.public_holidays (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  holiday_date date not null,
  name text not null check (length(trim(name)) between 2 and 120),
  is_paid boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, branch_id, holiday_date)
);

create table public.shift_roster_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  work_date date not null,
  starts_at time not null,
  ends_at time not null,
  break_minutes integer not null default 0 check (break_minutes between 0 and 360),
  status text not null default 'scheduled' check (status in ('scheduled','confirmed','swapped','cancelled')),
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_id, work_date),
  check (starts_at <> ends_at)
);

create table public.shift_swap_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  roster_entry_id uuid not null references public.shift_roster_entries(id) on delete cascade,
  requested_by_employee_id uuid not null references public.employees(id) on delete cascade,
  target_employee_id uuid references public.employees(id) on delete set null,
  reason text not null check (length(trim(reason)) between 5 and 500),
  status text not null default 'pending' check (status in ('pending','accepted','approved','rejected','cancelled')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.attendance_correction_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  work_date date not null,
  requested_check_in_at timestamptz,
  requested_check_out_at timestamptz,
  reason text not null check (length(trim(reason)) between 5 and 500),
  attachment_path text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references auth.users(id) on delete set null,
  review_note text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (requested_check_in_at is not null or requested_check_out_at is not null),
  check (requested_check_out_at is null or requested_check_in_at is null or requested_check_out_at > requested_check_in_at)
);

create table public.employee_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  document_type text not null check (document_type in ('cnic','contract','bank','certificate','warning','medical','termination','other')),
  title text not null check (length(trim(title)) between 2 and 120),
  storage_key text not null,
  expires_on date,
  is_confidential boolean not null default true,
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.employee_financial_profiles (
  employee_id uuid primary key references public.employees(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  bank_name text,
  account_title text,
  iban text,
  tax_number text,
  eobi_number text,
  tax_monthly_minor bigint not null default 0 check (tax_monthly_minor >= 0),
  eobi_monthly_minor bigint not null default 0 check (eobi_monthly_minor >= 0),
  updated_at timestamptz not null default now()
);

create table public.payroll_loans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  label text not null,
  principal_minor bigint not null check (principal_minor > 0),
  installment_minor bigint not null check (installment_minor > 0),
  outstanding_minor bigint not null check (outstanding_minor >= 0),
  starts_on date not null,
  status text not null default 'active' check (status in ('active','paused','settled','cancelled')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.payroll_reimbursements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  label text not null,
  amount_minor bigint not null check (amount_minor > 0),
  expense_date date not null,
  receipt_path text,
  reason text not null check (length(trim(reason)) between 5 and 500),
  status text not null default 'pending' check (status in ('pending','approved','rejected','applied','paid')),
  payroll_item_id uuid references public.payroll_items(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.payroll_loan_installments (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references public.payroll_loans(id) on delete cascade,
  payroll_item_id uuid not null references public.payroll_items(id) on delete cascade,
  amount_minor bigint not null check (amount_minor > 0),
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  unique (loan_id, payroll_item_id)
);

create table public.mobile_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  token text not null,
  platform text not null default 'ios' check (platform in ('ios','android')),
  environment text not null default 'production' check (environment in ('development','production')),
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, device_id),
  unique (token)
);

create table public.biometric_scan_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  device_id text not null,
  action text not null check (action in ('blink_turn_left','blink_turn_right','turn_left_blink','turn_right_blink')),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

alter table public.leave_types
  add column accrual_method text not null default 'annual' check (accrual_method in ('annual','monthly','joining_anniversary')),
  add column carry_forward_days numeric(6,2) not null default 0 check (carry_forward_days >= 0),
  add column attachment_after_days numeric(6,2) check (attachment_after_days is null or attachment_after_days >= 0);

alter table public.leave_requests
  add column duration_type text not null default 'full_day' check (duration_type in ('full_day','first_half','second_half','hourly')),
  add column requested_minutes integer check (requested_minutes is null or requested_minutes between 30 and 1440);

alter table public.payroll_item_components drop constraint if exists payroll_item_components_source_check;
alter table public.payroll_item_components add constraint payroll_item_components_source_check
  check(source in ('configured','attendance','leave','manual','system','statutory','loan','reimbursement'));

create table public.leave_approval_steps (
  id uuid primary key default gen_random_uuid(),
  leave_request_id uuid not null references public.leave_requests(id) on delete cascade,
  step_number integer not null check (step_number between 1 and 5),
  approver_role text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','skipped')),
  approver_user_id uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  note text,
  unique (leave_request_id, step_number)
);

create table public.leave_blackout_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  starts_on date not null,
  ends_on date not null,
  reason text not null check (length(trim(reason)) between 3 and 240),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create index shift_roster_branch_date_idx on public.shift_roster_entries(branch_id, work_date, status);
create index shift_roster_employee_date_idx on public.shift_roster_entries(employee_id, work_date desc);
create index shift_swap_status_idx on public.shift_swap_requests(branch_id, status, created_at desc);
create index correction_branch_status_idx on public.attendance_correction_requests(branch_id, status, created_at desc);
create index correction_employee_date_idx on public.attendance_correction_requests(employee_id, work_date desc);
create unique index correction_one_pending_per_day_idx on public.attendance_correction_requests(employee_id,work_date) where status='pending';
create index employee_documents_employee_idx on public.employee_documents(employee_id, created_at desc);
create index payroll_loans_employee_idx on public.payroll_loans(employee_id, status);
create index payroll_reimbursements_employee_idx on public.payroll_reimbursements(employee_id, status, expense_date desc);
create index mobile_push_tokens_user_idx on public.mobile_push_tokens(user_id) where is_active;
create index biometric_challenges_lookup_idx on public.biometric_scan_challenges(user_id, branch_id, device_id, expires_at desc) where consumed_at is null;
create index app_notifications_unread_user_idx on public.app_notifications(user_id, created_at desc) where is_read = false;

create trigger shift_roster_updated_at before update on public.shift_roster_entries for each row execute function public.set_updated_at();
create trigger financial_profile_updated_at before update on public.employee_financial_profiles for each row execute function public.set_updated_at();

alter table public.public_holidays enable row level security;
alter table public.shift_roster_entries enable row level security;
alter table public.shift_swap_requests enable row level security;
alter table public.attendance_correction_requests enable row level security;
alter table public.employee_documents enable row level security;
alter table public.employee_financial_profiles enable row level security;
alter table public.payroll_loans enable row level security;
alter table public.payroll_reimbursements enable row level security;
alter table public.payroll_loan_installments enable row level security;
alter table public.mobile_push_tokens enable row level security;
alter table public.biometric_scan_challenges enable row level security;
alter table public.leave_approval_steps enable row level security;
alter table public.leave_blackout_periods enable row level security;

create policy holidays_read on public.public_holidays for select to authenticated using (public.is_org_member(organization_id));
create policy holidays_manage on public.public_holidays for all to authenticated using (public.has_org_role(organization_id,array['owner','super_admin','hr_admin']) or (branch_id is not null and public.can_manage_branch(branch_id))) with check (public.has_org_role(organization_id,array['owner','super_admin','hr_admin']) or (branch_id is not null and public.can_manage_branch(branch_id)));
create policy roster_read on public.shift_roster_entries for select to authenticated using (public.is_employee_self(employee_id) or public.can_manage_branch(branch_id));
create policy roster_manage on public.shift_roster_entries for all to authenticated using (public.can_manage_branch(branch_id)) with check (public.can_manage_branch(branch_id));
create policy swaps_read on public.shift_swap_requests for select to authenticated using (public.is_employee_self(requested_by_employee_id) or (target_employee_id is not null and public.is_employee_self(target_employee_id)) or public.can_manage_branch(branch_id));
create policy swaps_insert on public.shift_swap_requests for insert to authenticated with check (public.is_employee_self(requested_by_employee_id));
create policy swaps_manage on public.shift_swap_requests for update to authenticated using (public.is_employee_self(requested_by_employee_id) or (target_employee_id is not null and public.is_employee_self(target_employee_id)) or public.can_manage_branch(branch_id));
create policy corrections_read on public.attendance_correction_requests for select to authenticated using (public.is_employee_self(employee_id) or public.can_manage_branch(branch_id));
create policy corrections_insert on public.attendance_correction_requests for insert to authenticated with check (public.is_employee_self(employee_id));
create policy corrections_manage on public.attendance_correction_requests for update to authenticated using (public.can_manage_branch(branch_id) or public.is_employee_self(employee_id));
create policy employee_documents_read on public.employee_documents for select to authenticated using (public.is_employee_self(employee_id) or public.has_org_role(organization_id,array['owner','super_admin','hr_admin']));
create policy employee_documents_manage on public.employee_documents for all to authenticated using (public.has_org_role(organization_id,array['owner','super_admin','hr_admin'])) with check (public.has_org_role(organization_id,array['owner','super_admin','hr_admin']));
create policy financial_profiles_read on public.employee_financial_profiles for select to authenticated using (public.is_employee_self(employee_id) or public.can_manage_payroll(organization_id));
create policy financial_profiles_manage on public.employee_financial_profiles for all to authenticated using (public.can_manage_payroll(organization_id)) with check (public.can_manage_payroll(organization_id));
create policy payroll_loans_read on public.payroll_loans for select to authenticated using (public.is_employee_self(employee_id) or public.can_manage_payroll(organization_id));
create policy payroll_loans_manage on public.payroll_loans for all to authenticated using (public.can_manage_payroll(organization_id)) with check (public.can_manage_payroll(organization_id));
create policy reimbursements_read on public.payroll_reimbursements for select to authenticated using (public.is_employee_self(employee_id) or public.can_manage_payroll(organization_id));
create policy reimbursements_insert on public.payroll_reimbursements for insert to authenticated with check (public.is_employee_self(employee_id) or public.can_manage_payroll(organization_id));
create policy reimbursements_manage on public.payroll_reimbursements for update to authenticated using (public.can_manage_payroll(organization_id));
create policy loan_installments_read on public.payroll_loan_installments for select to authenticated using (exists(select 1 from public.payroll_loans l where l.id=loan_id and (public.is_employee_self(l.employee_id) or public.can_manage_payroll(l.organization_id))));
create policy push_tokens_own on public.mobile_push_tokens for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy biometric_challenges_deny on public.biometric_scan_challenges for all to authenticated using (false) with check (false);
create policy approval_steps_read on public.leave_approval_steps for select to authenticated using (exists(select 1 from public.leave_requests r where r.id=leave_request_id and (public.is_employee_self(r.employee_id) or public.can_manage_branch(r.branch_id))));
create policy leave_blackouts_read on public.leave_blackout_periods for select to authenticated using(public.is_org_member(organization_id));
create policy leave_blackouts_manage on public.leave_blackout_periods for all to authenticated using(public.has_org_role(organization_id,array['owner','super_admin','hr_admin']) or (branch_id is not null and public.can_manage_branch(branch_id))) with check(public.has_org_role(organization_id,array['owner','super_admin','hr_admin']) or (branch_id is not null and public.can_manage_branch(branch_id)));

grant select,insert,update,delete on public.public_holidays,public.shift_roster_entries,public.shift_swap_requests,public.attendance_correction_requests,public.employee_documents,public.employee_financial_profiles,public.payroll_loans,public.payroll_reimbursements,public.payroll_loan_installments,public.mobile_push_tokens,public.leave_approval_steps,public.leave_blackout_periods to authenticated;
revoke all on public.biometric_scan_challenges from public,anon,authenticated;

create or replace function public.validate_operational_leave_request()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare leave_type public.leave_types%rowtype; working_days numeric(6,2);
begin
  select * into leave_type from public.leave_types where id=new.leave_type_id and organization_id=new.organization_id and is_active;
  if leave_type.id is null then raise exception 'leave type is unavailable'; end if;
  if exists(select 1 from public.leave_blackout_periods b where b.organization_id=new.organization_id and (b.branch_id is null or b.branch_id=new.branch_id) and daterange(b.starts_on,b.ends_on,'[]') && daterange(new.start_date,new.end_date,'[]')) then
    raise exception 'selected dates are unavailable for leave';
  end if;
  if exists(select 1 from public.leave_requests r where r.employee_id=new.employee_id and r.status in ('pending','approved') and daterange(r.start_date,r.end_date,'[]') && daterange(new.start_date,new.end_date,'[]')) then
    raise exception 'another leave request overlaps these dates';
  end if;
  if leave_type.requires_reason and length(trim(coalesce(new.reason,'')))<5 then raise exception 'leave reason is required'; end if;
  if (leave_type.requires_document or (leave_type.attachment_after_days is not null and new.requested_days>=leave_type.attachment_after_days)) and nullif(trim(coalesce(new.document_path,'')),'') is null then raise exception 'supporting document is required'; end if;
  if new.duration_type='full_day' then
    select count(*)::numeric into working_days from generate_series(new.start_date,new.end_date,interval '1 day') d
      where extract(isodow from d)<6 and not exists(select 1 from public.public_holidays h where h.organization_id=new.organization_id and (h.branch_id is null or h.branch_id=new.branch_id) and h.holiday_date=d::date);
    if working_days<=0 then raise exception 'selected dates contain no working days'; end if;
    new.requested_days:=working_days;new.requested_minutes:=null;
  elsif new.duration_type in ('first_half','second_half') then
    new.end_date:=new.start_date;new.requested_days:=0.5;new.requested_minutes:=240;
  elsif new.duration_type='hourly' then
    if new.requested_minutes is null then raise exception 'requested minutes are required'; end if;
    new.end_date:=new.start_date;new.requested_days:=round(new.requested_minutes::numeric/480,2);
  end if;
  return new;
end $$;

create trigger validate_operational_leave before insert on public.leave_requests for each row execute function public.validate_operational_leave_request();

create or replace function public.initialize_leave_approval_steps()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  insert into public.leave_approval_steps(leave_request_id,step_number,approver_role) values(new.id,1,'manager');
  if new.requested_days>3 then insert into public.leave_approval_steps(leave_request_id,step_number,approver_role) values(new.id,2,'hr'); end if;
  return new;
end $$;

create trigger initialize_leave_approval_steps after insert on public.leave_requests for each row execute function public.initialize_leave_approval_steps();

create or replace function public.review_leave_request(p_request_id uuid,p_status text,p_note text default null)
returns public.leave_requests language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r public.leave_requests%rowtype; step public.leave_approval_steps%rowtype; remaining integer;
begin
  if p_status not in ('approved','rejected') then raise exception 'invalid review status'; end if;
  select * into r from public.leave_requests where id=p_request_id for update;
  if r.id is null or r.status<>'pending' then raise exception 'request is not pending'; end if;
  select * into step from public.leave_approval_steps where leave_request_id=r.id and status='pending' order by step_number limit 1 for update;
  if step.id is null then raise exception 'approval workflow is complete'; end if;
  if step.approver_role='manager' and not public.can_manage_branch(r.branch_id) then raise exception 'manager approval required'; end if;
  if step.approver_role='hr' and not public.has_org_role(r.organization_id,array['owner','super_admin','hr_admin']) then raise exception 'HR approval required'; end if;
  update public.leave_approval_steps set status=p_status,approver_user_id=auth.uid(),reviewed_at=now(),note=nullif(trim(coalesce(p_note,'')),'') where id=step.id;
  if p_status='rejected' then
    update public.leave_approval_steps set status='skipped' where leave_request_id=r.id and status='pending';
    update public.leave_requests set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),review_note=p_note where id=r.id returning * into r;
  else
    select count(*) into remaining from public.leave_approval_steps where leave_request_id=r.id and status='pending';
    if remaining=0 then
      update public.leave_requests set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),review_note=p_note where id=r.id returning * into r;
      insert into public.leave_balance_ledger(organization_id,employee_id,leave_type_id,leave_request_id,entry_date,days_delta,entry_type,note,actor_user_id)
        values(r.organization_id,r.employee_id,r.leave_type_id,r.id,current_date,-r.requested_days,'approval',p_note,auth.uid());
    end if;
  end if;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,reason,metadata)
    values(r.organization_id,r.branch_id,auth.uid(),'leave.step_'||p_status,'leave_request',r.id,p_note,jsonb_build_object('step',step.step_number,'role',step.approver_role));
  return r;
end $$;

create or replace function public.review_attendance_correction(p_request_id uuid,p_status text,p_note text default null)
returns public.attendance_correction_requests
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r public.attendance_correction_requests%rowtype; daily public.attendance_daily%rowtype; worked integer;
begin
  select * into r from public.attendance_correction_requests where id=p_request_id for update;
  if r.id is null or not public.can_manage_branch(r.branch_id) then raise exception 'not permitted'; end if;
  if r.status<>'pending' or p_status not in ('approved','rejected') then raise exception 'invalid correction decision'; end if;
  if p_status='approved' then
    select * into daily from public.attendance_daily where employee_id=r.employee_id and work_date=r.work_date for update;
    if daily.id is null then
      insert into public.attendance_daily(organization_id,branch_id,employee_id,work_date,first_check_in_at,last_check_out_at,status)
      values(r.organization_id,r.branch_id,r.employee_id,r.work_date,r.requested_check_in_at,r.requested_check_out_at,'present') returning * into daily;
    else
      worked:=case when coalesce(r.requested_check_in_at,daily.first_check_in_at) is null or coalesce(r.requested_check_out_at,daily.last_check_out_at) is null then 0 else greatest(0,floor(extract(epoch from (coalesce(r.requested_check_out_at,daily.last_check_out_at)-coalesce(r.requested_check_in_at,daily.first_check_in_at)))/60)::integer) end;
      update public.attendance_daily set first_check_in_at=coalesce(r.requested_check_in_at,first_check_in_at),last_check_out_at=coalesce(r.requested_check_out_at,last_check_out_at),worked_minutes=worked,status='present' where id=daily.id;
    end if;
  end if;
  update public.attendance_correction_requests set status=p_status,reviewed_by=auth.uid(),review_note=nullif(trim(coalesce(p_note,'')),''),reviewed_at=now() where id=r.id returning * into r;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,reason,metadata) values(r.organization_id,r.branch_id,auth.uid(),'attendance.correction_'||p_status,'attendance_correction',r.id,p_note,jsonb_build_object('employee_id',r.employee_id,'work_date',r.work_date));
  return r;
end $$;

create or replace function public.review_shift_swap(p_request_id uuid,p_status text,p_note text default null)
returns public.shift_swap_requests
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r public.shift_swap_requests%rowtype; entry public.shift_roster_entries%rowtype;
begin
  select * into r from public.shift_swap_requests where id=p_request_id for update;
  if r.id is null or not public.can_manage_branch(r.branch_id) then raise exception 'not permitted'; end if;
  if r.status not in ('pending','accepted') or p_status not in ('approved','rejected') then raise exception 'invalid swap decision'; end if;
  if p_status='approved' then
    if r.target_employee_id is null then raise exception 'target employee required'; end if;
    update public.shift_roster_entries set employee_id=r.target_employee_id,status='swapped',notes=concat_ws(' · ',notes,'Approved shift swap') where id=r.roster_entry_id returning * into entry;
  end if;
  update public.shift_swap_requests set status=p_status,reviewed_by=auth.uid(),reviewed_at=now() where id=r.id returning * into r;
  return r;
end $$;

create or replace function public.apply_payroll_operations(p_run_id uuid)
returns integer
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r public.payroll_runs%rowtype; item record; amount bigint; applied integer:=0; loan record; reimbursement record; profile public.employee_financial_profiles%rowtype;
begin
  select * into r from public.payroll_runs where id=p_run_id for update;
  if r.id is null or not public.can_manage_payroll(r.organization_id) then raise exception 'not permitted'; end if;
  if r.status<>'draft' then raise exception 'payroll must be draft'; end if;
  for item in select * from public.payroll_items where payroll_run_id=r.id loop
    select * into profile from public.employee_financial_profiles where employee_id=item.employee_id;
    if profile.tax_monthly_minor>0 and not exists(select 1 from public.payroll_item_components where payroll_item_id=item.id and source='statutory' and label='Income tax') then
      insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item.id,'Income tax','deduction',profile.tax_monthly_minor,'statutory'); applied:=applied+1;
    end if;
    if profile.eobi_monthly_minor>0 and not exists(select 1 from public.payroll_item_components where payroll_item_id=item.id and source='statutory' and label='EOBI') then
      insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item.id,'EOBI','deduction',profile.eobi_monthly_minor,'statutory'); applied:=applied+1;
    end if;
    for loan in select * from public.payroll_loans where employee_id=item.employee_id and status='active' and starts_on<=r.period_end loop
      amount:=least(loan.installment_minor,loan.outstanding_minor);
      if amount>0 and not exists(select 1 from public.payroll_loan_installments where loan_id=loan.id and payroll_item_id=item.id) then
        insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item.id,loan.label,'deduction',amount,'loan');
        insert into public.payroll_loan_installments(loan_id,payroll_item_id,amount_minor) values(loan.id,item.id,amount); applied:=applied+1;
      end if;
    end loop;
    for reimbursement in select * from public.payroll_reimbursements where employee_id=item.employee_id and status='approved' and expense_date<=r.period_end loop
      insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item.id,reimbursement.label,'earning',reimbursement.amount_minor,'reimbursement');
      update public.payroll_reimbursements set status='applied',payroll_item_id=item.id where id=reimbursement.id; applied:=applied+1;
    end loop;
    update public.payroll_items pi set
      gross_minor=pi.prorated_base_minor+coalesce((select sum(amount_minor) from public.payroll_item_components where payroll_item_id=pi.id and component_type='earning'),0),
      deductions_minor=coalesce((select sum(amount_minor) from public.payroll_item_components where payroll_item_id=pi.id and component_type='deduction'),0)
      where pi.id=item.id;
    update public.payroll_items set net_minor=greatest(0,gross_minor-deductions_minor) where id=item.id;
  end loop;
  return applied;
end $$;

create or replace function public.settle_payroll_operations()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare installment record;
begin
  if new.status='paid' and old.status is distinct from 'paid' then
    for installment in select * from public.payroll_loan_installments where payroll_item_id=new.id and applied_at is null for update loop
      update public.payroll_loans set outstanding_minor=greatest(0,outstanding_minor-installment.amount_minor),status=case when outstanding_minor-installment.amount_minor<=0 then 'settled' else status end where id=installment.loan_id;
      update public.payroll_loan_installments set applied_at=now() where id=installment.id;
    end loop;
    update public.payroll_reimbursements set status='paid' where payroll_item_id=new.id and status='applied';
  end if;
  return new;
end $$;

create trigger settle_payroll_operations after update of status on public.payroll_items for each row execute function public.settle_payroll_operations();

create or replace function public.issue_biometric_challenge(p_branch_id uuid,p_device_id text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c public.biometric_scan_challenges%rowtype; recent integer; actions text[]:=array['blink_turn_left','blink_turn_right','turn_left_blink','turn_right_blink'];
begin
  if length(trim(coalesce(p_device_id,'')))<8 then raise exception 'invalid device identifier'; end if;
  if not exists(select 1 from public.branches b where b.id=p_branch_id and public.is_org_member(b.organization_id)) then raise exception 'not permitted'; end if;
  select count(*) into recent from public.biometric_scan_challenges where user_id=auth.uid() and created_at>now()-interval '1 minute';
  if recent>=8 then raise exception 'too many face scan attempts'; end if;
  insert into public.biometric_scan_challenges(user_id,branch_id,device_id,action,expires_at) values(auth.uid(),p_branch_id,p_device_id,actions[1+floor(random()*array_length(actions,1))::int],now()+interval '90 seconds') returning * into c;
  return jsonb_build_object('challengeId',c.id,'action',c.action,'expiresAt',c.expires_at);
end $$;

create or replace function public.register_mobile_push_token(p_device_id text,p_token text,p_environment text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  if length(trim(coalesce(p_device_id,'')))<8 or length(trim(coalesce(p_token,'')))<32 or p_environment not in ('development','production') then raise exception 'invalid push token'; end if;
  insert into public.mobile_push_tokens(user_id,device_id,token,environment) values(auth.uid(),p_device_id,trim(p_token),p_environment)
  on conflict(user_id,device_id) do update set token=excluded.token,environment=excluded.environment,is_active=true,last_seen_at=now();
  return true;
end $$;

create or replace function public.mobile_dashboard_summary(p_branch_id uuid,p_date date)
returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
select jsonb_build_object(
  'activeEmployees',(select count(*) from public.employee_branch_assignments a join public.employees e on e.id=a.employee_id where a.branch_id=p_branch_id and e.employment_status='active' and a.starts_on<=p_date and (a.ends_on is null or a.ends_on>=p_date)),
  'present',(select count(*) from public.attendance_daily where branch_id=p_branch_id and work_date=p_date and status='present'),
  'absent',(select count(*) from public.attendance_daily where branch_id=p_branch_id and work_date=p_date and status='absent'),
  'onLeave',(select count(*) from public.attendance_daily where branch_id=p_branch_id and work_date=p_date and status='leave'),
  'pendingCorrections',(select count(*) from public.attendance_correction_requests where branch_id=p_branch_id and status='pending'),
  'scheduledShifts',(select count(*) from public.shift_roster_entries where branch_id=p_branch_id and work_date=p_date and status<>'cancelled')
) where public.can_manage_branch(p_branch_id)
  or exists(select 1 from public.employee_branch_assignments a join public.employees e on e.id=a.employee_id where a.branch_id=p_branch_id and e.user_id=auth.uid())
  or exists(select 1 from public.branches b where b.id=p_branch_id and public.has_org_role(b.organization_id,array['owner','super_admin','hr_admin','payroll_admin','payroll_approver']));
$$;

create or replace function public.mobile_branch_employees(p_branch_id uuid,p_limit integer default 100,p_offset integer default 0)
returns setof public.employees language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select e.* from public.employee_branch_assignments a join public.employees e on e.id=a.employee_id
  where a.branch_id=p_branch_id and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date)
    and (public.can_manage_branch(p_branch_id) or e.user_id=auth.uid() or exists(select 1 from public.branches b where b.id=p_branch_id and public.has_org_role(b.organization_id,array['owner','super_admin','hr_admin','payroll_admin','payroll_approver'])))
  order by e.full_name limit least(greatest(p_limit,1),100) offset greatest(p_offset,0);
$$;

create or replace function public.mobile_branch_assignments(p_branch_id uuid,p_limit integer default 100,p_offset integer default 0)
returns setof public.employee_branch_assignments language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select a.* from public.employee_branch_assignments a join public.employees e on e.id=a.employee_id
  where a.branch_id=p_branch_id and (public.can_manage_branch(p_branch_id) or e.user_id=auth.uid() or exists(select 1 from public.branches b where b.id=p_branch_id and public.has_org_role(b.organization_id,array['owner','super_admin','hr_admin','payroll_admin','payroll_approver'])))
  order by a.starts_on desc limit least(greatest(p_limit,1),100) offset greatest(p_offset,0);
$$;

grant execute on function public.review_attendance_correction(uuid,text,text),public.review_shift_swap(uuid,text,text),public.apply_payroll_operations(uuid),public.issue_biometric_challenge(uuid,text),public.register_mobile_push_token(text,text,text),public.mobile_dashboard_summary(uuid,date),public.mobile_branch_employees(uuid,integer,integer),public.mobile_branch_assignments(uuid,integer,integer) to authenticated;

insert into realtime.channels(pattern,description,enabled) values('employee-hub:%','Role-scoped employee hub operational updates',true) on conflict(pattern) do update set enabled=true,description=excluded.description;
alter table realtime.channels enable row level security;
drop policy if exists employee_hub_subscribe on realtime.channels;
create policy employee_hub_subscribe on realtime.channels for select to authenticated using(
  pattern='employee-hub:%' and exists(
    select 1 from public.organization_memberships m
    where m.user_id=auth.uid() and m.organization_id=nullif(split_part(realtime.channel_name(),':',2),'')::uuid and m.is_active
  )
);

create or replace function public.publish_employee_hub_change()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare org uuid; branch uuid; record_id uuid; status_value text; payload jsonb;
begin
  payload:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  org:=nullif(payload->>'organization_id','')::uuid; branch:=nullif(payload->>'branch_id','')::uuid; record_id:=nullif(payload->>'id','')::uuid; status_value:=coalesce(payload->>'status','updated');
  perform realtime.publish('employee-hub:'||org::text,'data_changed',jsonb_build_object('table',tg_table_name,'id',record_id,'branchId',branch,'status',status_value));
  if tg_op='DELETE' then return old; else return new; end if;
end $$;

create trigger roster_realtime after insert or update or delete on public.shift_roster_entries for each row execute function public.publish_employee_hub_change();
create trigger correction_realtime after insert or update or delete on public.attendance_correction_requests for each row execute function public.publish_employee_hub_change();
create trigger leave_realtime after insert or update or delete on public.leave_requests for each row execute function public.publish_employee_hub_change();
create trigger payroll_realtime after insert or update or delete on public.payroll_runs for each row execute function public.publish_employee_hub_change();
create trigger notification_realtime after insert or update or delete on public.app_notifications for each row execute function public.publish_employee_hub_change();

drop policy if exists cb_documents_select on storage.objects;
drop policy if exists cb_documents_insert on storage.objects;
drop policy if exists cb_documents_update on storage.objects;
drop policy if exists cb_documents_delete on storage.objects;
create policy cb_documents_select on storage.objects for select to authenticated using(
  (bucket in ('leave-documents','employee-documents') and public.can_access_employee_document((storage.foldername(key))[2],false)) or
  (bucket='payslips' and public.can_access_employee_document((storage.foldername(key))[2],true))
);
create policy cb_documents_insert on storage.objects for insert to authenticated with check(
  uploaded_by=(select auth.jwt()->>'sub') and (
    (bucket in ('leave-documents','employee-documents') and public.can_access_employee_document((storage.foldername(key))[2],false)) or
    (bucket='payslips' and public.can_access_employee_document((storage.foldername(key))[2],true))
  )
);
create policy cb_documents_update on storage.objects for update to authenticated using(uploaded_by=(select auth.jwt()->>'sub')) with check(
  uploaded_by=(select auth.jwt()->>'sub') and (
    (bucket in ('leave-documents','employee-documents') and public.can_access_employee_document((storage.foldername(key))[2],false)) or
    (bucket='payslips' and public.can_access_employee_document((storage.foldername(key))[2],true))
  )
);
create policy cb_documents_delete on storage.objects for delete to authenticated using(
  uploaded_by=(select auth.jwt()->>'sub') and (
    (bucket in ('leave-documents','employee-documents') and public.can_access_employee_document((storage.foldername(key))[2],false)) or
    (bucket='payslips' and public.can_access_employee_document((storage.foldername(key))[2],true))
  )
);

comment on table public.employee_documents is 'Private employee file metadata; binary objects live in the employee-documents storage bucket.';
comment on table public.mobile_push_tokens is 'APNs/FCM tokens. Tokens are private and available only to trusted server functions.';
