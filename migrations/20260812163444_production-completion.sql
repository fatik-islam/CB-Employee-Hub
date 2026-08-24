alter table public.schedule_templates
  add column if not exists check_in_time time not null default '09:00',
  add column if not exists check_out_time time not null default '17:00',
  add column if not exists break_minutes integer not null default 0 check (break_minutes between 0 and 240),
  add column if not exists overtime_after_minutes integer not null default 480 check (overtime_after_minutes between 1 and 1440);

alter table public.attendance_daily
  add column if not exists scheduled_minutes integer not null default 0 check (scheduled_minutes >= 0),
  add column if not exists late_minutes integer not null default 0 check (late_minutes >= 0),
  add column if not exists overtime_minutes integer not null default 0 check (overtime_minutes >= 0),
  add column if not exists shortfall_minutes integer not null default 0 check (shortfall_minutes >= 0);

alter table public.app_settings
  add column if not exists deduct_unpaid_leave boolean not null default true,
  add column if not exists deduct_absent_days boolean not null default true,
  add column if not exists deduct_late_minutes boolean not null default false,
  add column if not exists pay_overtime boolean not null default true,
  add column if not exists overtime_multiplier numeric(5,2) not null default 1.50 check (overtime_multiplier between 1 and 5);

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 120),
  message text not null check (length(trim(message)) between 2 and 500),
  category text not null check (category in ('attendance','leave','payroll','employee','security','system')),
  entity_type text,
  entity_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists app_notifications_user_created_idx
  on public.app_notifications(user_id,is_read,created_at desc);

alter table public.app_notifications enable row level security;
drop policy if exists app_notifications_select on public.app_notifications;
drop policy if exists app_notifications_update on public.app_notifications;
create policy app_notifications_select on public.app_notifications for select to authenticated
  using (user_id=auth.uid());
create policy app_notifications_update on public.app_notifications for update to authenticated
  using (user_id=auth.uid()) with check (user_id=auth.uid());
grant select,update on public.app_notifications to authenticated;
revoke insert,delete on public.app_notifications from authenticated;

create or replace function public.notify_user(
  p_organization_id uuid,p_user_id uuid,p_title text,p_message text,p_category text,
  p_entity_type text default null,p_entity_id uuid default null
) returns uuid
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare result_id uuid;
begin
  insert into public.app_notifications(organization_id,user_id,title,message,category,entity_type,entity_id)
  values(p_organization_id,p_user_id,trim(p_title),trim(p_message),p_category,p_entity_type,p_entity_id)
  returning id into result_id;
  return result_id;
end;
$$;
revoke all on function public.notify_user(uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;

create or replace function public.set_employee_status(p_employee_id uuid,p_status text,p_reason text default null)
returns public.employees
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare e public.employees%rowtype;
begin
  select * into e from public.employees where id=p_employee_id for update;
  if e.id is null then raise exception 'employee not found'; end if;
  if not public.has_org_role(e.organization_id,array['owner','super_admin','hr_admin'])
     and not exists(select 1 from public.employee_branch_assignments a where a.employee_id=e.id and a.ends_on is null and public.can_manage_branch(a.branch_id))
  then raise exception 'not permitted'; end if;
  if p_status not in ('active','inactive','terminated') then raise exception 'invalid employee status'; end if;
  if p_status<>'active' and length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason is required'; end if;

  update public.employees set employment_status=p_status,
    termination_date=case when p_status='terminated' then current_date else null end
    where id=e.id returning * into e;
  if p_status='active' then
    update public.organization_memberships set is_active=true where user_id=e.user_id and organization_id=e.organization_id;
    update public.branch_memberships bm set is_active=true
      where bm.user_id=e.user_id and exists(select 1 from public.employee_branch_assignments a where a.employee_id=e.id and a.branch_id=bm.branch_id and a.ends_on is null);
  else
    update public.organization_memberships set is_active=false where user_id=e.user_id and organization_id=e.organization_id;
    update public.branch_memberships set is_active=false where user_id=e.user_id;
    update public.employee_invites set status='revoked' where employee_id=e.id and status='pending';
  end if;
  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,reason,metadata)
    values(e.organization_id,auth.uid(),'employee.'||p_status,'employee',e.id,nullif(trim(coalesce(p_reason,'')),''),jsonb_build_object('employee_code',e.employee_code));
  if e.user_id is not null then perform public.notify_user(e.organization_id,e.user_id,'Account updated','Your employment status is now '||p_status||'.','employee','employee',e.id); end if;
  return e;
end;
$$;

create or replace function public.assign_employee_branch(p_employee_id uuid,p_branch_id uuid,p_is_primary boolean,p_starts_on date)
returns public.employee_branch_assignments
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare e public.employees%rowtype; b public.branches%rowtype; a public.employee_branch_assignments%rowtype;
begin
  select * into e from public.employees where id=p_employee_id;
  select * into b from public.branches where id=p_branch_id and is_active;
  if e.id is null or b.id is null or e.organization_id<>b.organization_id then raise exception 'invalid employee or branch'; end if;
  if not public.has_org_role(e.organization_id,array['owner','super_admin','hr_admin']) and not public.can_manage_branch(b.id) then raise exception 'not permitted'; end if;
  if p_is_primary then update public.employee_branch_assignments set is_primary=false where employee_id=e.id and ends_on is null; end if;
  insert into public.employee_branch_assignments(employee_id,branch_id,is_primary,starts_on)
  values(e.id,b.id,p_is_primary,p_starts_on)
  on conflict(employee_id,branch_id,starts_on) do update set ends_on=null,is_primary=excluded.is_primary
  returning * into a;
  if e.user_id is not null then
    insert into public.branch_memberships(branch_id,user_id,role,is_active)
    values(b.id,e.user_id,case when e.app_role='manager' then 'manager' else 'employee' end,true)
    on conflict(branch_id,user_id) do update set is_active=true,role=excluded.role;
  end if;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(e.organization_id,b.id,auth.uid(),'employee.branch_assigned','employee',e.id,jsonb_build_object('primary',p_is_primary,'starts_on',p_starts_on));
  return a;
end;
$$;

create or replace function public.end_employee_branch_assignment(p_assignment_id uuid,p_reason text)
returns public.employee_branch_assignments
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare a public.employee_branch_assignments%rowtype; e public.employees%rowtype;
begin
  select * into a from public.employee_branch_assignments where id=p_assignment_id for update;
  select * into e from public.employees where id=a.employee_id;
  if a.id is null or length(trim(coalesce(p_reason,'')))<5 then raise exception 'assignment and reason are required'; end if;
  if not public.has_org_role(e.organization_id,array['owner','super_admin','hr_admin']) and not public.can_manage_branch(a.branch_id) then raise exception 'not permitted'; end if;
  update public.employee_branch_assignments set ends_on=greatest(starts_on,current_date),is_primary=false where id=a.id returning * into a;
  if e.user_id is not null then update public.branch_memberships set is_active=false where branch_id=a.branch_id and user_id=e.user_id; end if;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,reason)
    values(e.organization_id,a.branch_id,auth.uid(),'employee.branch_ended','employee',e.id,trim(p_reason));
  return a;
end;
$$;

create or replace function public.cancel_leave_request(p_request_id uuid,p_reason text default null)
returns public.leave_requests
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare r public.leave_requests%rowtype; was_approved boolean; target_user uuid;
begin
  select * into r from public.leave_requests where id=p_request_id for update;
  if r.id is null or r.status not in ('pending','approved') then raise exception 'leave cannot be cancelled'; end if;
  if not public.is_employee_self(r.employee_id) and not public.can_manage_branch(r.branch_id) and not public.has_org_role(r.organization_id,array['owner','super_admin','hr_admin']) then raise exception 'not permitted'; end if;
  if r.status='approved' and length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason is required'; end if;
  was_approved:=r.status='approved';
  update public.leave_requests set status='cancelled',reviewed_at=now(),reviewed_by=auth.uid(),review_note=nullif(trim(coalesce(p_reason,'')),'') where id=r.id returning * into r;
  if was_approved then
    insert into public.leave_balance_ledger(organization_id,employee_id,leave_type_id,leave_request_id,entry_date,days_delta,entry_type,note,actor_user_id)
    values(r.organization_id,r.employee_id,r.leave_type_id,r.id,current_date,r.requested_days,'reversal','Cancelled leave',auth.uid());
  end if;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,reason)
    values(r.organization_id,r.branch_id,auth.uid(),'leave.cancelled','leave_request',r.id,nullif(trim(coalesce(p_reason,'')),''));
  select user_id into target_user from public.employees where id=r.employee_id;
  if target_user is not null then perform public.notify_user(r.organization_id,target_user,'Leave cancelled','Your leave request was cancelled.','leave','leave_request',r.id); end if;
  return r;
end;
$$;

create or replace function public.correct_attendance_day(
  p_attendance_id uuid,p_first_check_in_at timestamptz,p_last_check_out_at timestamptz,p_status text,p_reason text
) returns public.attendance_daily
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare d public.attendance_daily%rowtype; old_row jsonb; minutes integer;
begin
  select * into d from public.attendance_daily where id=p_attendance_id for update;
  if d.id is null or not public.can_manage_branch(d.branch_id) then raise exception 'not permitted'; end if;
  if p_status not in ('present','absent','leave','partial') or length(trim(coalesce(p_reason,'')))<5 then raise exception 'valid status and reason are required'; end if;
  if p_first_check_in_at is not null and p_last_check_out_at is not null and p_last_check_out_at<p_first_check_in_at then raise exception 'check-out must be after check-in'; end if;
  old_row:=to_jsonb(d);
  minutes:=case when p_first_check_in_at is null or p_last_check_out_at is null then 0 else greatest(0,floor(extract(epoch from (p_last_check_out_at-p_first_check_in_at))/60)::integer) end;
  update public.attendance_daily set first_check_in_at=p_first_check_in_at,last_check_out_at=p_last_check_out_at,worked_minutes=minutes,status=p_status,
    overtime_minutes=greatest(0,minutes-scheduled_minutes),shortfall_minutes=greatest(0,scheduled_minutes-minutes)
    where id=d.id returning * into d;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,reason,metadata)
    values(d.organization_id,d.branch_id,auth.uid(),'attendance.corrected','attendance_daily',d.id,trim(p_reason),jsonb_build_object('before',old_row,'after',to_jsonb(d)));
  return d;
end;
$$;

create or replace function public.deactivate_my_account(p_reason text)
returns boolean
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare m public.organization_memberships%rowtype; owner_count integer; employee_id uuid;
begin
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason is required'; end if;
  select * into m from public.organization_memberships where user_id=auth.uid() and is_active order by created_at limit 1 for update;
  if m.id is null then raise exception 'active account not found'; end if;
  if m.role='owner' then
    select count(*) into owner_count from public.organization_memberships where organization_id=m.organization_id and role='owner' and is_active;
    if owner_count<=1 then raise exception 'assign another owner before deactivating this account'; end if;
  end if;
  select id into employee_id from public.employees where organization_id=m.organization_id and user_id=auth.uid();
  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,reason)
    values(m.organization_id,auth.uid(),'account.deactivated','user',auth.uid(),trim(p_reason));
  update public.organization_memberships set is_active=false where user_id=auth.uid();
  update public.branch_memberships set is_active=false where user_id=auth.uid();
  update public.employees set employment_status='inactive' where id=employee_id;
  return true;
end;
$$;

create or replace function public.prepare_payroll_run(p_run_id uuid)
returns integer
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare
  r public.payroll_runs%rowtype; e record; item_id uuid; total_days numeric; eligible numeric;
  prorated bigint; earnings bigint; deductions bigint; component_amount bigint; unpaid_days numeric;
  absent_days numeric; late_total integer; overtime_total integer; daily_rate numeric; minute_rate numeric;
  settings public.app_settings%rowtype; c record; a record; added integer:=0;
begin
  select * into r from public.payroll_runs where id=p_run_id for update;
  if r.id is null or r.status<>'draft' then raise exception 'payroll run must be draft'; end if;
  if not public.can_manage_payroll(r.organization_id) then raise exception 'not permitted'; end if;
  select * into settings from public.app_settings where organization_id=r.organization_id;
  update public.payroll_adjustments set status='pending',payroll_run_id=null where payroll_run_id=r.id and status='applied';
  delete from public.payroll_items where payroll_run_id=r.id;
  for e in
    select emp.*,cv.id compensation_id,cv.base_salary_minor
    from public.employees emp
    join lateral(select * from public.compensation_versions c where c.employee_id=emp.id and c.effective_from<=r.period_end and (c.effective_to is null or c.effective_to>=r.period_start) order by c.effective_from desc limit 1) cv on true
    where emp.organization_id=r.organization_id and emp.employment_status in ('active','inactive','terminated') and emp.joining_date<=r.period_end and (emp.termination_date is null or emp.termination_date>=r.period_start)
      and (r.branch_id is null or exists(select 1 from public.employee_branch_assignments ba where ba.employee_id=emp.id and ba.branch_id=r.branch_id and ba.starts_on<=r.period_end and (ba.ends_on is null or ba.ends_on>=r.period_start)))
  loop
    total_days:=public.scheduled_working_days(e.id,r.period_start,r.period_end);
    if total_days=0 then raise exception 'schedule is not configured for employee %',e.employee_code; end if;
    eligible:=public.scheduled_working_days(e.id,greatest(r.period_start,e.joining_date),least(r.period_end,coalesce(e.termination_date,r.period_end)));
    prorated:=round(e.base_salary_minor*eligible/total_days)::bigint;
    earnings:=prorated; deductions:=0; daily_rate:=e.base_salary_minor/total_days; minute_rate:=daily_rate/480;
    insert into public.payroll_items(payroll_run_id,employee_id,compensation_version_id,scheduled_days,eligible_days,base_salary_minor,prorated_base_minor,gross_minor,deductions_minor,net_minor)
      values(r.id,e.id,e.compensation_id,total_days,eligible,e.base_salary_minor,prorated,prorated,0,prorated) returning id into item_id;
    insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item_id,'Prorated base salary','earning',prorated,'system');

    for c in select d.*,esc.amount_minor,esc.percentage from public.employee_salary_components esc join public.salary_component_definitions d on d.id=esc.component_definition_id
      where esc.employee_id=e.id and d.is_active and esc.effective_from<=r.period_end and (esc.effective_to is null or esc.effective_to>=r.period_start)
    loop
      component_amount:=coalesce(c.amount_minor,round(prorated*c.percentage/100)::bigint);
      insert into public.payroll_item_components(payroll_item_id,component_definition_id,label,component_type,amount_minor,source)
        values(item_id,c.id,c.name,c.component_type,component_amount,'configured');
      if c.component_type='earning' then earnings:=earnings+component_amount; else deductions:=deductions+component_amount; end if;
    end loop;

    select coalesce(sum(lr.requested_days),0) into unpaid_days from public.leave_requests lr join public.leave_types lt on lt.id=lr.leave_type_id
      where lr.employee_id=e.id and lr.status='approved' and not lt.is_paid and lr.start_date<=r.period_end and lr.end_date>=r.period_start;
    if settings.deduct_unpaid_leave and unpaid_days>0 then
      component_amount:=round(daily_rate*least(unpaid_days,eligible))::bigint; deductions:=deductions+component_amount;
      insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item_id,'Unpaid leave','deduction',component_amount,'leave');
    end if;
    select count(*) filter(where status='absent'),coalesce(sum(late_minutes),0),coalesce(sum(overtime_minutes),0)
      into absent_days,late_total,overtime_total from public.attendance_daily where employee_id=e.id and work_date between r.period_start and r.period_end;
    if settings.deduct_absent_days and absent_days>0 then
      component_amount:=round(daily_rate*absent_days)::bigint; deductions:=deductions+component_amount;
      insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item_id,'Absence','deduction',component_amount,'attendance');
    end if;
    if settings.deduct_late_minutes and late_total>0 then
      component_amount:=round(minute_rate*late_total)::bigint; deductions:=deductions+component_amount;
      insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item_id,'Late arrival','deduction',component_amount,'attendance');
    end if;
    if settings.pay_overtime and overtime_total>0 then
      component_amount:=round(minute_rate*overtime_total*settings.overtime_multiplier)::bigint; earnings:=earnings+component_amount;
      insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item_id,'Overtime','earning',component_amount,'attendance');
    end if;
    for a in select * from public.payroll_adjustments where organization_id=r.organization_id and employee_id=e.id and status='pending' and payroll_run_id is null order by created_at
    loop
      insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source) values(item_id,a.label,a.component_type,a.amount_minor,'manual');
      if a.component_type='earning' then earnings:=earnings+a.amount_minor; else deductions:=deductions+a.amount_minor; end if;
      update public.payroll_adjustments set status='applied',payroll_run_id=r.id where id=a.id;
    end loop;
    update public.payroll_items set gross_minor=earnings,deductions_minor=deductions,net_minor=greatest(0,earnings-deductions) where id=item_id;
    added:=added+1;
  end loop;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(r.organization_id,r.branch_id,auth.uid(),'payroll.prepared','payroll_run',r.id,jsonb_build_object('items',added,'attendance_aware',true));
  return added;
end;
$$;

revoke all on function public.set_employee_status(uuid,text,text),public.assign_employee_branch(uuid,uuid,boolean,date),
  public.end_employee_branch_assignment(uuid,text),public.cancel_leave_request(uuid,text),
  public.correct_attendance_day(uuid,timestamptz,timestamptz,text,text),public.deactivate_my_account(text)
  from public,anon;
grant execute on function public.set_employee_status(uuid,text,text),public.assign_employee_branch(uuid,uuid,boolean,date),
  public.end_employee_branch_assignment(uuid,text),public.cancel_leave_request(uuid,text),
  public.correct_attendance_day(uuid,timestamptz,timestamptz,text,text),public.deactivate_my_account(text)
  to authenticated;

revoke update,delete on public.audit_events,public.attendance_attempts,public.attendance_events,public.attendance_overrides,public.leave_balance_ledger,public.salary_payments from authenticated;
