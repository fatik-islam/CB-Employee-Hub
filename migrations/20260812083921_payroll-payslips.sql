create table public.employee_payroll_profiles (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  pay_frequency text not null default 'monthly' check (pay_frequency in ('monthly')),
  pay_day smallint not null check (pay_day between 1 and 31),
  cutoff_day smallint not null check (cutoff_day between 1 and 31),
  effective_from date not null,
  effective_to date,
  created_at timestamptz not null default now(),
  unique(employee_id,effective_from),
  check(effective_to is null or effective_to>=effective_from)
);

create table public.compensation_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  base_salary_minor bigint not null check(base_salary_minor>=0),
  currency char(3) not null default 'PKR',
  effective_from date not null,
  effective_to date,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(employee_id,effective_from),
  check(effective_to is null or effective_to>=effective_from)
);

create table public.salary_component_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  component_type text not null check(component_type in ('earning','deduction')),
  calculation_type text not null check(calculation_type in ('fixed','percentage')),
  is_taxable boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(organization_id,code)
);

create table public.employee_salary_components (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  component_definition_id uuid not null references public.salary_component_definitions(id) on delete restrict,
  amount_minor bigint,
  percentage numeric(7,4),
  effective_from date not null,
  effective_to date,
  created_at timestamptz not null default now(),
  unique(employee_id,component_definition_id,effective_from),
  check((amount_minor is not null and percentage is null) or (amount_minor is null and percentage is not null)),
  check(amount_minor is null or amount_minor>=0),
  check(percentage is null or percentage between 0 and 100),
  check(effective_to is null or effective_to>=effective_from)
);

create table public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete restrict,
  title text not null,
  period_start date not null,
  period_end date not null,
  currency char(3) not null default 'PKR',
  status text not null default 'draft' check(status in ('draft','submitted','approved','locked','cancelled')),
  prepared_by uuid not null references auth.users(id) on delete restrict,
  submitted_at timestamptz,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  locked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(period_end>=period_start),
  check(approved_by is null or approved_by<>prepared_by)
);

create table public.payroll_items (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references public.payroll_runs(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete restrict,
  compensation_version_id uuid not null references public.compensation_versions(id) on delete restrict,
  scheduled_days numeric(6,2) not null check(scheduled_days>=0),
  eligible_days numeric(6,2) not null check(eligible_days>=0),
  base_salary_minor bigint not null,
  prorated_base_minor bigint not null,
  gross_minor bigint not null,
  deductions_minor bigint not null default 0,
  net_minor bigint not null,
  status text not null default 'draft' check(status in ('draft','approved','paid','void')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(payroll_run_id,employee_id)
);

create table public.payroll_item_components (
  id uuid primary key default gen_random_uuid(),
  payroll_item_id uuid not null references public.payroll_items(id) on delete cascade,
  component_definition_id uuid references public.salary_component_definitions(id) on delete restrict,
  label text not null,
  component_type text not null check(component_type in ('earning','deduction')),
  amount_minor bigint not null check(amount_minor>=0),
  source text not null check(source in ('configured','attendance','leave','manual','system')),
  created_at timestamptz not null default now()
);

create table public.payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  payroll_run_id uuid references public.payroll_runs(id) on delete set null,
  component_type text not null check(component_type in ('earning','deduction')),
  label text not null,
  amount_minor bigint not null check(amount_minor>0),
  reason text not null,
  status text not null default 'pending' check(status in ('pending','applied','cancelled')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.salary_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  payroll_item_id uuid not null references public.payroll_items(id) on delete restrict,
  amount_minor bigint not null check(amount_minor>0),
  currency char(3) not null default 'PKR',
  payment_method text not null check(payment_method in ('cash','bank_transfer','cheque','other')),
  reference text,
  paid_on date not null,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.payslip_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  payroll_item_id uuid not null unique references public.payroll_items(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  storage_path text not null,
  generated_at timestamptz not null default now(),
  generated_by uuid references auth.users(id) on delete set null
);

create index compensation_employee_effective_idx on public.compensation_versions(employee_id,effective_from desc);
create index payroll_runs_org_period_idx on public.payroll_runs(organization_id,period_end desc);
create index payroll_items_employee_idx on public.payroll_items(employee_id,created_at desc);
create index payments_item_idx on public.salary_payments(payroll_item_id,paid_on);
create trigger payroll_runs_updated_at before update on public.payroll_runs for each row execute function public.set_updated_at();
create trigger payroll_items_updated_at before update on public.payroll_items for each row execute function public.set_updated_at();

create or replace function public.can_manage_payroll(target_org uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp
as $$ select public.has_org_role(target_org,array['owner','super_admin','payroll_admin']); $$;

create or replace function public.can_approve_payroll(target_org uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp
as $$ select public.has_org_role(target_org,array['owner','super_admin','payroll_approver']); $$;

create or replace function public.scheduled_working_days(p_employee uuid,p_start date,p_end date)
returns numeric
language sql
stable
security definer
set search_path=pg_catalog,public,pg_temp
as $$
  with assignment as (
    select st.weekly_rules from public.employee_schedule_assignments esa
    join public.schedule_templates st on st.id=esa.schedule_template_id
    where esa.employee_id=p_employee and esa.effective_from<=p_end and (esa.effective_to is null or esa.effective_to>=p_start)
    order by esa.effective_from desc limit 1
  )
  select count(*)::numeric from generate_series(p_start,p_end,interval '1 day') d
  left join assignment a on true
  where coalesce((a.weekly_rules->extract(isodow from d)::int::text->>'working')::boolean,extract(isodow from d)<6);
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
    eligible:=public.scheduled_working_days(e.id,greatest(r.period_start,e.joining_date),least(r.period_end,coalesce(e.termination_date,r.period_end)));
    prorated:=case when total_days=0 then 0 else round(e.base_salary_minor*eligible/total_days)::bigint end;
    insert into public.payroll_items(payroll_run_id,employee_id,compensation_version_id,scheduled_days,eligible_days,base_salary_minor,prorated_base_minor,gross_minor,net_minor)
      values(r.id,e.id,e.compensation_id,total_days,eligible,e.base_salary_minor,prorated,prorated,prorated);
    added:=added+1;
  end loop;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata) values(r.organization_id,r.branch_id,auth.uid(),'payroll.prepared','payroll_run',r.id,jsonb_build_object('items',added));
  return added;
end;
$$;

create or replace function public.transition_payroll_run(p_run_id uuid,p_status text)
returns public.payroll_runs
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare r public.payroll_runs%rowtype;
begin
  select * into r from public.payroll_runs where id=p_run_id for update;
  if r.id is null then raise exception 'payroll run not found'; end if;
  if p_status='submitted' and r.status='draft' and public.can_manage_payroll(r.organization_id) then
    update public.payroll_runs set status='submitted',submitted_at=now() where id=r.id returning * into r;
  elsif p_status='approved' and r.status='submitted' and public.can_approve_payroll(r.organization_id) then
    if r.prepared_by=auth.uid() then raise exception 'maker cannot approve own payroll'; end if;
    update public.payroll_runs set status='approved',approved_by=auth.uid(),approved_at=now() where id=r.id returning * into r;
    update public.payroll_items set status='approved' where payroll_run_id=r.id;
  elsif p_status='locked' and r.status='approved' and public.can_approve_payroll(r.organization_id) then
    update public.payroll_runs set status='locked',locked_at=now() where id=r.id returning * into r;
  else raise exception 'invalid or unauthorized transition'; end if;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id) values(r.organization_id,r.branch_id,auth.uid(),'payroll.'||p_status,'payroll_run',r.id);
  return r;
end;
$$;

alter table public.employee_payroll_profiles enable row level security;
alter table public.compensation_versions enable row level security;
alter table public.salary_component_definitions enable row level security;
alter table public.employee_salary_components enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_items enable row level security;
alter table public.payroll_item_components enable row level security;
alter table public.payroll_adjustments enable row level security;
alter table public.salary_payments enable row level security;
alter table public.payslip_documents enable row level security;

create policy payroll_profile_select on public.employee_payroll_profiles for select to authenticated using(public.is_employee_self(employee_id) or exists(select 1 from public.employees e where e.id=employee_id and public.can_manage_payroll(e.organization_id)));
create policy payroll_profile_manage on public.employee_payroll_profiles for all to authenticated using(exists(select 1 from public.employees e where e.id=employee_id and public.can_manage_payroll(e.organization_id))) with check(exists(select 1 from public.employees e where e.id=employee_id and public.can_manage_payroll(e.organization_id)));
create policy compensation_select on public.compensation_versions for select to authenticated using(public.is_employee_self(employee_id) or public.can_manage_payroll(organization_id));
create policy compensation_manage on public.compensation_versions for all to authenticated using(public.can_manage_payroll(organization_id)) with check(public.can_manage_payroll(organization_id));
create policy component_defs_select on public.salary_component_definitions for select to authenticated using(public.is_org_member(organization_id));
create policy component_defs_manage on public.salary_component_definitions for all to authenticated using(public.can_manage_payroll(organization_id)) with check(public.can_manage_payroll(organization_id));
create policy employee_components_select on public.employee_salary_components for select to authenticated using(public.is_employee_self(employee_id) or exists(select 1 from public.employees e where e.id=employee_id and public.can_manage_payroll(e.organization_id)));
create policy employee_components_manage on public.employee_salary_components for all to authenticated using(exists(select 1 from public.employees e where e.id=employee_id and public.can_manage_payroll(e.organization_id))) with check(exists(select 1 from public.employees e where e.id=employee_id and public.can_manage_payroll(e.organization_id)));
create policy payroll_runs_select on public.payroll_runs for select to authenticated using(public.can_manage_payroll(organization_id) or public.can_approve_payroll(organization_id));
create policy payroll_runs_manage on public.payroll_runs for all to authenticated using(public.can_manage_payroll(organization_id)) with check(public.can_manage_payroll(organization_id));
create policy payroll_items_select on public.payroll_items for select to authenticated using(public.is_employee_self(employee_id) or exists(select 1 from public.payroll_runs r where r.id=payroll_run_id and (public.can_manage_payroll(r.organization_id) or public.can_approve_payroll(r.organization_id))));
create policy payroll_items_manage on public.payroll_items for all to authenticated using(exists(select 1 from public.payroll_runs r where r.id=payroll_run_id and r.status='draft' and public.can_manage_payroll(r.organization_id))) with check(exists(select 1 from public.payroll_runs r where r.id=payroll_run_id and r.status='draft' and public.can_manage_payroll(r.organization_id)));
create policy item_components_select on public.payroll_item_components for select to authenticated using(exists(select 1 from public.payroll_items i where i.id=payroll_item_id and (public.is_employee_self(i.employee_id) or exists(select 1 from public.payroll_runs r where r.id=i.payroll_run_id and (public.can_manage_payroll(r.organization_id) or public.can_approve_payroll(r.organization_id))))));
create policy adjustments_select on public.payroll_adjustments for select to authenticated using(public.is_employee_self(employee_id) or public.can_manage_payroll(organization_id));
create policy adjustments_manage on public.payroll_adjustments for all to authenticated using(public.can_manage_payroll(organization_id)) with check(public.can_manage_payroll(organization_id));
create policy payments_select on public.salary_payments for select to authenticated using(public.can_manage_payroll(organization_id) or exists(select 1 from public.payroll_items i where i.id=payroll_item_id and public.is_employee_self(i.employee_id)));
create policy payments_insert on public.salary_payments for insert to authenticated with check(public.can_manage_payroll(organization_id));
create policy payslips_select on public.payslip_documents for select to authenticated using(public.is_employee_self(employee_id) or public.can_manage_payroll(organization_id));
create policy payslips_manage on public.payslip_documents for all to authenticated using(public.can_manage_payroll(organization_id)) with check(public.can_manage_payroll(organization_id));

grant select,insert,update,delete on public.employee_payroll_profiles,public.compensation_versions,public.salary_component_definitions,public.employee_salary_components,public.payroll_runs,public.payroll_items,public.payroll_item_components,public.payroll_adjustments,public.payslip_documents to authenticated;
grant select,insert on public.salary_payments to authenticated;
grant execute on function public.prepare_payroll_run(uuid),public.transition_payroll_run(uuid,text) to authenticated;
revoke update,delete on public.salary_payments from authenticated;
