insert into public.organizations(id,name,default_currency,timezone)
values('10000000-0000-4000-8000-000000000001','Chicky Bites','PKR','Asia/Karachi');

insert into public.branches(id,organization_id,code,name,geofence_radius_m,attendance_verification_mode,requires_biometric,timezone)
values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','MAIN','Main Branch',50,'IP_OR_GPS',true,'Asia/Karachi');

insert into public.app_settings(organization_id)
values('10000000-0000-4000-8000-000000000001');

insert into public.leave_types(id,organization_id,code,name,is_paid,default_annual_days,requires_document,requires_reason,effective_from)
values
('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','SICK','Sick Leave',false,0,false,true,'2026-01-01'),
('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','URGENT','Urgent Leave',false,0,false,true,'2026-01-01'),
('30000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','NORMAL','Normal Leave',false,0,false,true,'2026-01-01');

insert into public.schedule_templates(id,organization_id,branch_id,name,weekly_rules,grace_minutes,expected_minutes_per_day)
values(
  '40000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'Legacy schedule – configure before payroll',
  '{"1":{"working":false},"2":{"working":false},"3":{"working":false},"4":{"working":false},"5":{"working":false},"6":{"working":false},"7":{"working":false}}'::jsonb,
  0,
  480
);

insert into public.employees(id,organization_id,employee_code,full_name,phone,cnic,address,position,joining_date,employment_status,legacy_id,created_at)
values(
  '20f30ffc-193f-4197-ab8a-86a727089f06',
  '10000000-0000-4000-8000-000000000001',
  'CB-001',
  'Syed Fatik Islam',
  '+923127300556',
  '34201-6532867-1',
  'Cantt road Domailaan Chowk Jalalpur Jattan, 50780 Gujrat',
  'Dev',
  '2026-02-23',
  'active',
  '20f30ffc-193f-4197-ab8a-86a727089f06',
  '2026-02-23 16:55:48+05'
);

insert into public.employee_branch_assignments(employee_id,branch_id,is_primary,starts_on)
values('20f30ffc-193f-4197-ab8a-86a727089f06','20000000-0000-4000-8000-000000000001',true,'2026-02-23');

insert into public.employee_schedule_assignments(employee_id,schedule_template_id,effective_from)
values('20f30ffc-193f-4197-ab8a-86a727089f06','40000000-0000-4000-8000-000000000001','2026-02-23');

insert into public.employee_payroll_profiles(employee_id,pay_frequency,pay_day,cutoff_day,effective_from)
values('20f30ffc-193f-4197-ab8a-86a727089f06','monthly',24,23,'2026-02-23');

insert into public.leave_requests(id,organization_id,branch_id,employee_id,leave_type_id,start_date,end_date,requested_days,reason,status,reviewed_at,legacy_id,created_at)
values
('1cc8292b-14a2-405e-91c0-f0248f575c51','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','20f30ffc-193f-4197-ab8a-86a727089f06','30000000-0000-4000-8000-000000000001','2026-02-23','2026-02-24',2,'sick leave','rejected','2026-02-23 16:56:22+05','1cc8292b-14a2-405e-91c0-f0248f575c51','2026-02-23 16:56:05+05'),
('3d2e3f28-1f3f-418c-85aa-2757effcb4b7','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','20f30ffc-193f-4197-ab8a-86a727089f06','30000000-0000-4000-8000-000000000001','2026-02-23','2026-02-23',1,'sick leave','approved','2026-02-23 16:56:35+05','3d2e3f28-1f3f-418c-85aa-2757effcb4b7','2026-02-23 16:56:33+05');

insert into public.leave_balance_ledger(organization_id,employee_id,leave_type_id,leave_request_id,entry_date,days_delta,entry_type,note)
values('10000000-0000-4000-8000-000000000001','20f30ffc-193f-4197-ab8a-86a727089f06','30000000-0000-4000-8000-000000000001','3d2e3f28-1f3f-418c-85aa-2757effcb4b7','2026-02-23',-1,'approval','Imported from legacy SQLite');

insert into public.attendance_attempts(id,request_id,organization_id,branch_id,employee_id,event_type,biometric_passed,outcome,created_at)
values(
  '50000000-0000-4000-8000-000000000001','9b86a3cc-54f0-4bd9-a4f3-a3aa0b4de730','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','20f30ffc-193f-4197-ab8a-86a727089f06','check_in',true,'accepted','2026-02-25 18:58:44+05'
);

insert into public.attendance_events(id,attempt_id,organization_id,branch_id,employee_id,event_type,occurred_at,local_work_date,source,created_at)
values(
  '9b86a3cc-54f0-4bd9-a4f3-a3aa0b4de730','50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','20f30ffc-193f-4197-ab8a-86a727089f06','check_in','2026-02-25 18:58:44+05','2026-02-25','legacy_import','2026-02-25 18:58:44+05'
);

insert into public.attendance_daily(organization_id,branch_id,employee_id,work_date,first_check_in_at,status)
values
('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','20f30ffc-193f-4197-ab8a-86a727089f06','2026-02-23',null,'leave'),
('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','20f30ffc-193f-4197-ab8a-86a727089f06','2026-02-25','2026-02-25 18:58:44+05','present');

insert into public.audit_events(organization_id,branch_id,action,entity_type,entity_id,metadata,created_at)
values
('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','legacy.employee_imported','employee','20f30ffc-193f-4197-ab8a-86a727089f06','{"source":"chickybites.db"}'::jsonb,now()),
('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','legacy.biometric_requires_reenrollment','employee','20f30ffc-193f-4197-ab8a-86a727089f06','{"legacy_face_profiles":1,"legacy_biometric_logs":24,"template_migrated":false}'::jsonb,now());

create or replace function public.bootstrap_organization(org_name text, branch_name text, branch_code text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare target_org uuid; target_branch uuid; caller_name text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if exists(select 1 from public.organization_memberships where user_id=auth.uid()) then raise exception 'user already belongs to an organization'; end if;
  select id into target_org from public.organizations where not exists(select 1 from public.organization_memberships m where m.organization_id=organizations.id) order by created_at limit 1 for update;
  if target_org is null then raise exception 'initial organization already claimed'; end if;
  select id into target_branch from public.branches where organization_id=target_org order by created_at limit 1;
  caller_name:=coalesce(nullif(trim(auth.jwt()->>'name'),''),nullif(split_part(auth.jwt()->>'email','@',1),''),'Owner');
  insert into public.profiles(user_id,full_name) values(auth.uid(),caller_name) on conflict(user_id) do nothing;
  insert into public.organization_memberships(organization_id,user_id,role) values(target_org,auth.uid(),'owner');
  insert into public.branch_memberships(branch_id,user_id,role,can_override_attendance) values(target_branch,auth.uid(),'branch_admin',true);
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id) values(target_org,target_branch,auth.uid(),'organization.claimed','organization',target_org);
  return jsonb_build_object('organization_id',target_org,'branch_id',target_branch);
end;
$$;

create or replace function public.prepare_payroll_run(p_run_id uuid)
returns integer
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare r public.payroll_runs%rowtype; e record; total_days numeric; eligible numeric; prorated bigint; added integer:=0;
begin
  select * into r from public.payroll_runs where id=p_run_id for update;
  if r.id is null or r.status<>'draft' then raise exception 'payroll run must be draft'; end if;
  if not public.can_manage_payroll(r.organization_id) then raise exception 'not permitted'; end if;
  delete from public.payroll_items where payroll_run_id=r.id;
  for e in
    select emp.*,cv.id compensation_id,cv.base_salary_minor
    from public.employees emp
    join lateral(select * from public.compensation_versions c where c.employee_id=emp.id and c.effective_from<=r.period_end and (c.effective_to is null or c.effective_to>=r.period_start) order by c.effective_from desc limit 1) cv on true
    where emp.organization_id=r.organization_id and emp.joining_date<=r.period_end and (emp.termination_date is null or emp.termination_date>=r.period_start)
      and (r.branch_id is null or exists(select 1 from public.employee_branch_assignments a where a.employee_id=emp.id and a.branch_id=r.branch_id and a.starts_on<=r.period_end and (a.ends_on is null or a.ends_on>=r.period_start)))
  loop
    total_days:=public.scheduled_working_days(e.id,r.period_start,r.period_end);
    if total_days=0 then raise exception 'schedule is not configured for employee %',e.employee_code; end if;
    eligible:=public.scheduled_working_days(e.id,greatest(r.period_start,e.joining_date),least(r.period_end,coalesce(e.termination_date,r.period_end)));
    prorated:=round(e.base_salary_minor*eligible/total_days)::bigint;
    insert into public.payroll_items(payroll_run_id,employee_id,compensation_version_id,scheduled_days,eligible_days,base_salary_minor,prorated_base_minor,gross_minor,net_minor)
      values(r.id,e.id,e.compensation_id,total_days,eligible,e.base_salary_minor,prorated,prorated,prorated);
    added:=added+1;
  end loop;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata) values(r.organization_id,r.branch_id,auth.uid(),'payroll.prepared','payroll_run',r.id,jsonb_build_object('items',added));
  return added;
end;
$$;
