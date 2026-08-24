create table public.salary_transaction_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  code text not null,
  name text not null check(length(trim(name)) between 2 and 120),
  description text,
  transaction_type text not null check(transaction_type in ('earning','deduction')),
  category text not null check(category in ('late_checkin','early_checkout','absence','unpaid_leave','overtime','extra_food','loan','tax','eobi','reimbursement','bonus','penalty','allowance','custom')),
  calculation_method text not null check(calculation_method in ('fixed','per_minute','per_hour','per_occurrence','percentage_base','quantity_rate')),
  rate_minor bigint check(rate_minor is null or rate_minor >= 0),
  percentage numeric(7,4) check(percentage is null or percentage between 0 and 100),
  grace_minutes integer not null default 0 check(grace_minutes between 0 and 1440),
  daily_cap_minor bigint check(daily_cap_minor is null or daily_cap_minor >= 0),
  monthly_cap_minor bigint check(monthly_cap_minor is null or monthly_cap_minor >= 0),
  scope_type text not null default 'all' check(scope_type in ('all','branch','employee','department','position')),
  scope_value text,
  approval_required boolean not null default true,
  allow_dispute boolean not null default true,
  auto_generate boolean not null default false,
  effective_from date not null default current_date,
  effective_to date,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,code,effective_from),
  check(effective_to is null or effective_to >= effective_from),
  check((calculation_method='percentage_base' and percentage is not null) or (calculation_method<>'percentage_base' and rate_minor is not null)),
  check((scope_type='all' and scope_value is null) or (scope_type<>'all' and nullif(trim(scope_value),'') is not null))
);

create table public.salary_food_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  name text not null check(length(trim(name)) between 2 and 120),
  unit_label text not null default 'item' check(length(trim(unit_label)) between 1 and 30),
  unit_price_minor bigint not null check(unit_price_minor > 0),
  effective_from date not null default current_date,
  effective_to date,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,branch_id,name,effective_from),
  check(effective_to is null or effective_to >= effective_from)
);

create table public.salary_ledger_transactions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  rule_id uuid references public.salary_transaction_rules(id) on delete restrict,
  payroll_item_id uuid references public.payroll_items(id) on delete restrict,
  reversal_of_id uuid references public.salary_ledger_transactions(id) on delete restrict,
  transaction_type text not null check(transaction_type in ('earning','deduction','payment')),
  category text not null,
  label text not null check(length(trim(label)) between 2 and 120),
  description text not null check(length(trim(description)) between 2 and 500),
  amount_minor bigint not null check(amount_minor > 0),
  currency char(3) not null default 'PKR',
  status text not null default 'pending' check(status in ('pending','approved','rejected','disputed','applied','paid','reversed')),
  occurred_at timestamptz not null default now(),
  work_date date,
  source_type text not null check(source_type in ('manual','attendance','food','leave','loan','reimbursement','payroll_component','payment','system','reversal')),
  source_id uuid,
  quantity numeric(10,2),
  unit_rate_minor bigint,
  calculation_minutes integer,
  calculation_text text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  check(quantity is null or quantity > 0),
  check(unit_rate_minor is null or unit_rate_minor >= 0),
  check(calculation_minutes is null or calculation_minutes >= 0),
  check(reversal_of_id is null or source_type='reversal')
);

create table public.salary_transaction_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  transaction_id uuid not null references public.salary_ledger_transactions(id) on delete restrict,
  event_type text not null check(event_type in ('created','approved','rejected','disputed','dispute_resolved','applied','paid','reversed','recalculated')),
  from_status text,
  to_status text,
  note text,
  actor_user_id uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.salary_transaction_disputes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  transaction_id uuid not null references public.salary_ledger_transactions(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  reason text not null check(length(trim(reason)) between 5 and 1000),
  status text not null default 'open' check(status in ('open','under_review','accepted','rejected','resolved')),
  resolution_note text,
  created_by_user_id uuid not null references auth.users(id) on delete restrict default auth.uid(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index salary_dispute_one_open_idx on public.salary_transaction_disputes(transaction_id)
where status in ('open','under_review');
create index salary_rules_effective_idx on public.salary_transaction_rules(organization_id,category,effective_from desc) where is_active;
create index salary_food_effective_idx on public.salary_food_items(organization_id,branch_id,effective_from desc) where is_active;
create index salary_ledger_employee_cursor_idx on public.salary_ledger_transactions(employee_id,occurred_at desc,id desc);
create index salary_ledger_org_status_idx on public.salary_ledger_transactions(organization_id,status,occurred_at desc);
create index salary_ledger_period_idx on public.salary_ledger_transactions(employee_id,work_date,transaction_type,status);
create index salary_ledger_source_idx on public.salary_ledger_transactions(source_type,source_id,rule_id) where source_id is not null;
create index salary_events_transaction_idx on public.salary_transaction_events(transaction_id,created_at);
create index salary_disputes_org_status_idx on public.salary_transaction_disputes(organization_id,status,created_at desc);

create trigger salary_rules_updated_at before update on public.salary_transaction_rules for each row execute function public.set_updated_at();
create trigger salary_food_updated_at before update on public.salary_food_items for each row execute function public.set_updated_at();
create trigger salary_disputes_updated_at before update on public.salary_transaction_disputes for each row execute function public.set_updated_at();

create or replace function public.can_view_employee_salary(p_employee_id uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
  select exists(
    select 1 from public.employees e
    where e.id=p_employee_id and (
      e.user_id=auth.uid() or public.can_manage_payroll(e.organization_id) or public.can_approve_payroll(e.organization_id)
    )
  );
$$;

create or replace function public.protect_salary_ledger_core()
returns trigger language plpgsql set search_path=pg_catalog,public,pg_temp as $$
begin
  if new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.employee_id is distinct from old.employee_id
    or new.rule_id is distinct from old.rule_id
    or new.reversal_of_id is distinct from old.reversal_of_id
    or new.transaction_type is distinct from old.transaction_type
    or new.category is distinct from old.category
    or new.label is distinct from old.label
    or new.description is distinct from old.description
    or new.amount_minor is distinct from old.amount_minor
    or new.currency is distinct from old.currency
    or new.occurred_at is distinct from old.occurred_at
    or new.work_date is distinct from old.work_date
    or new.source_type is distinct from old.source_type
    or new.source_id is distinct from old.source_id
    or new.quantity is distinct from old.quantity
    or new.unit_rate_minor is distinct from old.unit_rate_minor
    or new.calculation_minutes is distinct from old.calculation_minutes
    or new.calculation_text is distinct from old.calculation_text
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'salary transaction history is immutable; use a reversal';
  end if;
  return new;
end;
$$;

create trigger protect_salary_ledger_core before update on public.salary_ledger_transactions
for each row execute function public.protect_salary_ledger_core();

create or replace function public.salary_rule_applies(p_rule public.salary_transaction_rules,p_employee public.employees,p_branch_id uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
  select (p_rule.branch_id is null or p_rule.branch_id=p_branch_id)
    and case p_rule.scope_type
      when 'all' then true
      when 'branch' then p_rule.scope_value=p_branch_id::text
      when 'employee' then p_rule.scope_value=p_employee.id::text
      when 'department' then lower(p_rule.scope_value)=lower(coalesce(p_employee.department,''))
      when 'position' then lower(p_rule.scope_value)=lower(coalesce(p_employee.position,''))
      else false end;
$$;

create or replace function public.salary_rule_amount(
  p_rule public.salary_transaction_rules,p_employee_id uuid,p_metric numeric,p_work_date date,p_exclude_source_id uuid default null
)
returns bigint language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
declare base_minor bigint:=0; raw_amount bigint:=0; used_day bigint:=0; used_month bigint:=0;
begin
  if p_rule.calculation_method='percentage_base' then
    select coalesce(c.base_salary_minor,0) into base_minor from public.compensation_versions c
      where c.employee_id=p_employee_id and c.effective_from<=p_work_date
        and (c.effective_to is null or c.effective_to>=p_work_date)
      order by c.effective_from desc limit 1;
    raw_amount:=round(base_minor*coalesce(p_rule.percentage,0)/100)::bigint;
  elsif p_rule.calculation_method='fixed' or p_rule.calculation_method='per_occurrence' then raw_amount:=coalesce(p_rule.rate_minor,0);
  elsif p_rule.calculation_method='per_minute' then raw_amount:=round(greatest(0,p_metric-p_rule.grace_minutes)*coalesce(p_rule.rate_minor,0))::bigint;
  elsif p_rule.calculation_method='per_hour' then raw_amount:=ceil(greatest(0,p_metric-p_rule.grace_minutes)/60.0)::bigint*coalesce(p_rule.rate_minor,0);
  elsif p_rule.calculation_method='quantity_rate' then raw_amount:=round(greatest(0,p_metric)*coalesce(p_rule.rate_minor,0))::bigint;
  end if;
  select coalesce(sum(amount_minor),0) into used_day from public.salary_ledger_transactions
    where employee_id=p_employee_id and rule_id=p_rule.id and work_date=p_work_date and status not in ('rejected','reversed')
      and (p_exclude_source_id is null or source_id is distinct from p_exclude_source_id);
  select coalesce(sum(amount_minor),0) into used_month from public.salary_ledger_transactions
    where employee_id=p_employee_id and rule_id=p_rule.id and work_date>=date_trunc('month',p_work_date)::date
      and work_date<(date_trunc('month',p_work_date)+interval '1 month')::date and status not in ('rejected','reversed')
      and (p_exclude_source_id is null or source_id is distinct from p_exclude_source_id);
  if p_rule.daily_cap_minor is not null then raw_amount:=least(raw_amount,greatest(0,p_rule.daily_cap_minor-used_day)); end if;
  if p_rule.monthly_cap_minor is not null then raw_amount:=least(raw_amount,greatest(0,p_rule.monthly_cap_minor-used_month)); end if;
  return greatest(0,raw_amount);
end;
$$;

create or replace function public.create_salary_transaction(
  p_employee_id uuid,p_branch_id uuid,p_rule_id uuid,p_transaction_type text,p_category text,
  p_label text,p_description text,p_amount_minor bigint,p_occurred_at timestamptz,p_work_date date,
  p_source_type text,p_source_id uuid,p_quantity numeric,p_unit_rate_minor bigint,p_calculation_minutes integer,p_calculation_text text
)
returns public.salary_ledger_transactions language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare e public.employees%rowtype; r public.salary_transaction_rules%rowtype; result public.salary_ledger_transactions%rowtype; initial_status text;
begin
  select * into e from public.employees where id=p_employee_id;
  if e.id is null then raise exception 'employee not found'; end if;
  if p_rule_id is not null then select * into r from public.salary_transaction_rules where id=p_rule_id and organization_id=e.organization_id; end if;
  if public.can_manage_payroll(e.organization_id) then null;
  elsif p_category='extra_food' and p_branch_id is not null and public.can_manage_branch(p_branch_id) then null;
  else raise exception 'not permitted'; end if;
  if p_amount_minor<=0 or p_transaction_type not in ('earning','deduction') then raise exception 'invalid transaction'; end if;
  initial_status:=case when r.id is not null and not r.approval_required and public.can_manage_payroll(e.organization_id) then 'approved' else 'pending' end;
  insert into public.salary_ledger_transactions(organization_id,branch_id,employee_id,rule_id,transaction_type,category,label,description,amount_minor,status,occurred_at,work_date,source_type,source_id,quantity,unit_rate_minor,calculation_minutes,calculation_text,approved_by,approved_at)
  values(e.organization_id,p_branch_id,p_employee_id,p_rule_id,p_transaction_type,p_category,trim(p_label),trim(p_description),p_amount_minor,initial_status,coalesce(p_occurred_at,now()),coalesce(p_work_date,(coalesce(p_occurred_at,now()) at time zone 'Asia/Karachi')::date),p_source_type,p_source_id,p_quantity,p_unit_rate_minor,p_calculation_minutes,p_calculation_text,case when initial_status='approved' then auth.uid() end,case when initial_status='approved' then now() end)
  returning * into result;
  insert into public.salary_transaction_events(organization_id,transaction_id,event_type,to_status,note)
  values(e.organization_id,result.id,'created',result.status,result.calculation_text);
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,reason,metadata)
  values(e.organization_id,p_branch_id,auth.uid(),'salary.transaction_created','salary_transaction',result.id,result.description,jsonb_build_object('employee_id',e.id,'amount_minor',result.amount_minor,'type',result.transaction_type));
  return result;
end;
$$;

create or replace function public.record_salary_food_charge(p_employee_id uuid,p_food_item_id uuid,p_quantity numeric,p_occurred_at timestamptz,p_note text)
returns public.salary_ledger_transactions language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare food public.salary_food_items%rowtype; employee public.employees%rowtype; amount bigint;
begin
  select * into food from public.salary_food_items where id=p_food_item_id and is_active
    and effective_from<=coalesce((p_occurred_at at time zone 'Asia/Karachi')::date,current_date)
    and (effective_to is null or effective_to>=coalesce((p_occurred_at at time zone 'Asia/Karachi')::date,current_date));
  select * into employee from public.employees where id=p_employee_id;
  if food.id is null or employee.id is null or employee.organization_id<>food.organization_id then raise exception 'invalid food charge'; end if;
  if not (public.can_manage_payroll(food.organization_id) or (food.branch_id is not null and public.can_manage_branch(food.branch_id))) then raise exception 'not permitted'; end if;
  if p_quantity<=0 or p_quantity>100 then raise exception 'invalid quantity'; end if;
  amount:=round(food.unit_price_minor*p_quantity)::bigint;
  return public.create_salary_transaction(employee.id,food.branch_id,null,'deduction','extra_food',food.name,
    trim(food.name||' × '||p_quantity||' '||food.unit_label||case when nullif(trim(coalesce(p_note,'')),'') is null then '' else ' • '||trim(p_note) end),
    amount,coalesce(p_occurred_at,now()),coalesce((p_occurred_at at time zone 'Asia/Karachi')::date,current_date),'food',food.id,p_quantity,food.unit_price_minor,null,
    p_quantity||' × PKR '||to_char(food.unit_price_minor/100.0,'FM999G999G999D00'));
end;
$$;

create or replace function public.review_salary_transaction(p_transaction_id uuid,p_status text,p_note text)
returns public.salary_ledger_transactions language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare t public.salary_ledger_transactions%rowtype; old_status text; target_user uuid;
begin
  select * into t from public.salary_ledger_transactions where id=p_transaction_id for update;
  if t.id is null or not public.can_approve_payroll(t.organization_id) then raise exception 'not permitted'; end if;
  if t.status not in ('pending','disputed') or p_status not in ('approved','rejected') then raise exception 'invalid transition'; end if;
  old_status:=t.status;
  update public.salary_ledger_transactions set status=p_status,approved_by=case when p_status='approved' then auth.uid() else null end,approved_at=case when p_status='approved' then now() else null end where id=t.id returning * into t;
  insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note)
  values(t.organization_id,t.id,p_status,old_status,p_status,nullif(trim(p_note),''));
  select user_id into target_user from public.employees where id=t.employee_id;
  if target_user is not null then perform public.notify_user(t.organization_id,target_user,'Salary transaction '||p_status,t.label||' was '||p_status||'.','payroll','salary_transaction',t.id); end if;
  return t;
end;
$$;

create or replace function public.dispute_salary_transaction(p_transaction_id uuid,p_reason text)
returns public.salary_transaction_disputes language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare t public.salary_ledger_transactions%rowtype; e public.employees%rowtype; d public.salary_transaction_disputes%rowtype;
begin
  select * into t from public.salary_ledger_transactions where id=p_transaction_id for update;
  select * into e from public.employees where id=t.employee_id;
  if t.id is null or e.user_id<>auth.uid() then raise exception 'not permitted'; end if;
  if t.status not in ('pending','approved','applied') then raise exception 'this transaction cannot be disputed'; end if;
  if not coalesce((select allow_dispute from public.salary_transaction_rules where id=t.rule_id),true) then raise exception 'disputes are disabled for this transaction'; end if;
  insert into public.salary_transaction_disputes(organization_id,transaction_id,employee_id,reason)
  values(t.organization_id,t.id,t.employee_id,trim(p_reason)) returning * into d;
  update public.salary_ledger_transactions set status='disputed' where id=t.id;
  insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note)
  values(t.organization_id,t.id,'disputed',t.status,'disputed',trim(p_reason));
  return d;
end;
$$;

create or replace function public.resolve_salary_dispute(p_dispute_id uuid,p_status text,p_note text)
returns public.salary_transaction_disputes language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare d public.salary_transaction_disputes%rowtype; t public.salary_ledger_transactions%rowtype; final_status text;
begin
  select * into d from public.salary_transaction_disputes where id=p_dispute_id for update;
  if d.id is null or not public.can_approve_payroll(d.organization_id) or d.status not in ('open','under_review') then raise exception 'not permitted'; end if;
  if p_status not in ('accepted','rejected') then raise exception 'invalid resolution'; end if;
  select * into t from public.salary_ledger_transactions where id=d.transaction_id for update;
  final_status:=case when p_status='accepted' then 'rejected' else 'approved' end;
  update public.salary_transaction_disputes set status=p_status,resolution_note=trim(p_note),reviewed_by=auth.uid(),reviewed_at=now() where id=d.id returning * into d;
  update public.salary_ledger_transactions set status=final_status,approved_by=case when final_status='approved' then auth.uid() end,approved_at=case when final_status='approved' then now() end where id=t.id;
  insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note)
  values(t.organization_id,t.id,'dispute_resolved','disputed',final_status,trim(p_note));
  return d;
end;
$$;

create or replace function public.reverse_salary_transaction(p_transaction_id uuid,p_reason text)
returns public.salary_ledger_transactions language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare original public.salary_ledger_transactions%rowtype; result public.salary_ledger_transactions%rowtype;
begin
  select * into original from public.salary_ledger_transactions where id=p_transaction_id for update;
  if original.id is null or not public.can_approve_payroll(original.organization_id) then raise exception 'not permitted'; end if;
  if original.status not in ('approved','applied','paid') or exists(select 1 from public.salary_ledger_transactions where reversal_of_id=original.id) then raise exception 'transaction cannot be reversed'; end if;
  insert into public.salary_ledger_transactions(organization_id,branch_id,employee_id,rule_id,reversal_of_id,transaction_type,category,label,description,amount_minor,status,occurred_at,work_date,source_type,source_id,created_by,approved_by,approved_at)
  values(original.organization_id,original.branch_id,original.employee_id,original.rule_id,original.id,case when original.transaction_type='deduction' then 'earning' else 'deduction' end,original.category,'Reversal: '||original.label,trim(p_reason),original.amount_minor,'approved',now(),current_date,'reversal',original.id,auth.uid(),auth.uid(),now()) returning * into result;
  update public.salary_ledger_transactions set status='reversed' where id=original.id;
  insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note)
  values(original.organization_id,original.id,'reversed',original.status,'reversed',trim(p_reason));
  insert into public.salary_transaction_events(organization_id,transaction_id,event_type,to_status,note)
  values(original.organization_id,result.id,'created','approved','Reversal of '||original.id);
  return result;
end;
$$;

create or replace function public.employee_salary_summary(p_employee_id uuid default null,p_as_of date default current_date)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
declare employee_id uuid; e public.employees%rowtype; base bigint:=0; approved_earnings bigint:=0; approved_deductions bigint:=0; pending_deductions bigint:=0; paid bigint:=0; pay_day integer:=1; period_start date; period_end date; next_pay date;
begin
  employee_id:=p_employee_id;
  if employee_id is null then select id into employee_id from public.employees where user_id=auth.uid() limit 1; end if;
  if employee_id is null or not public.can_view_employee_salary(employee_id) then raise exception 'not permitted'; end if;
  select * into e from public.employees where id=employee_id;
  period_start:=date_trunc('month',p_as_of)::date; period_end:=(date_trunc('month',p_as_of)+interval '1 month-1 day')::date;
  select coalesce(base_salary_minor,0) into base from public.compensation_versions where employee_id=e.id and effective_from<=p_as_of and (effective_to is null or effective_to>=p_as_of) order by effective_from desc limit 1;
  select coalesce(sum(case when transaction_type='earning' then amount_minor else 0 end),0),coalesce(sum(case when transaction_type='deduction' then amount_minor else 0 end),0)
    into approved_earnings,approved_deductions from public.salary_ledger_transactions where employee_id=e.id and work_date between period_start and period_end and status in ('approved','applied','paid');
  select coalesce(sum(amount_minor),0) into pending_deductions from public.salary_ledger_transactions where employee_id=e.id and work_date between period_start and period_end and transaction_type='deduction' and status in ('pending','disputed');
  select coalesce(sum(sp.amount_minor),0) into paid from public.salary_payments sp join public.payroll_items pi on pi.id=sp.payroll_item_id join public.payroll_runs pr on pr.id=pi.payroll_run_id where pi.employee_id=e.id and sp.paid_on between period_start and period_end;
  select coalesce(pay_day,1) into pay_day from public.employee_payroll_profiles where employee_id=e.id and effective_from<=p_as_of and (effective_to is null or effective_to>=p_as_of) order by effective_from desc limit 1;
  next_pay:=make_date(extract(year from p_as_of)::int,extract(month from p_as_of)::int,least(pay_day,extract(day from period_end)::int));
  if next_pay<p_as_of then next_pay:=(date_trunc('month',p_as_of)+interval '1 month')::date+(least(pay_day,extract(day from ((date_trunc('month',p_as_of)+interval '2 month-1 day')::date))::int)-1); end if;
  return jsonb_build_object('employeeId',e.id,'currency','PKR','periodStart',period_start,'periodEnd',period_end,'baseSalaryMinor',base,'approvedEarningsMinor',approved_earnings,'approvedDeductionsMinor',approved_deductions,'pendingDeductionsMinor',pending_deductions,'estimatedNetMinor',greatest(0,base+approved_earnings-approved_deductions-pending_deductions),'confirmedNetMinor',greatest(0,base+approved_earnings-approved_deductions),'paidMinor',paid,'remainingMinor',greatest(0,base+approved_earnings-approved_deductions-paid),'nextPayDate',next_pay);
end;
$$;

create or replace function public.salary_ledger_page(
  p_employee_id uuid default null,p_from timestamptz default null,p_to timestamptz default null,
  p_transaction_type text default null,p_category text default null,p_status text default null,p_search text default null,
  p_before_at timestamptz default null,p_before_id uuid default null,p_limit integer default 20
)
returns table(id uuid,organization_id uuid,branch_id uuid,employee_id uuid,rule_id uuid,payroll_item_id uuid,reversal_of_id uuid,transaction_type text,category text,label text,description text,amount_minor bigint,currency char(3),status text,occurred_at timestamptz,work_date date,source_type text,source_id uuid,quantity numeric,unit_rate_minor bigint,calculation_minutes integer,calculation_text text,created_by uuid,approved_by uuid,approved_at timestamptz,applied_at timestamptz,created_at timestamptz,has_more boolean)
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare employee_id uuid; requested_limit integer:=least(greatest(p_limit,1),50);
begin
  employee_id:=p_employee_id;
  if employee_id is null then select e.id into employee_id from public.employees e where e.user_id=auth.uid() limit 1; end if;
  if employee_id is null or not public.can_view_employee_salary(employee_id) then raise exception 'not permitted'; end if;
  return query with filtered as(
    select t.* from public.salary_ledger_transactions t where t.employee_id=employee_id
      and (p_from is null or t.occurred_at>=p_from) and (p_to is null or t.occurred_at<=p_to)
      and (p_transaction_type is null or t.transaction_type=p_transaction_type)
      and (p_category is null or t.category=p_category) and (p_status is null or t.status=p_status)
      and (nullif(trim(p_search),'') is null or t.label ilike '%'||trim(p_search)||'%' or t.description ilike '%'||trim(p_search)||'%')
      and (p_before_at is null or (t.occurred_at,t.id)<(p_before_at,p_before_id))
    order by t.occurred_at desc,t.id desc limit requested_limit+1
  )
  select f.id,f.organization_id,f.branch_id,f.employee_id,f.rule_id,f.payroll_item_id,f.reversal_of_id,f.transaction_type,f.category,f.label,f.description,f.amount_minor,f.currency,f.status,f.occurred_at,f.work_date,f.source_type,f.source_id,f.quantity,f.unit_rate_minor,f.calculation_minutes,f.calculation_text,f.created_by,f.approved_by,f.approved_at,f.applied_at,f.created_at,(select count(*)>requested_limit from filtered)
  from filtered f order by f.occurred_at desc,f.id desc limit requested_limit;
end;
$$;

create or replace function public.materialize_attendance_salary_transactions()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare e public.employees%rowtype; rule_row public.salary_transaction_rules%rowtype; metric numeric; amount bigint; existing public.salary_ledger_transactions%rowtype; description_text text;
begin
  select * into e from public.employees where id=new.employee_id;
  for rule_row in select * from public.salary_transaction_rules r where r.organization_id=new.organization_id and r.is_active and r.auto_generate and r.category in ('late_checkin','early_checkout','absence','overtime') and r.effective_from<=new.work_date and (r.effective_to is null or r.effective_to>=new.work_date) order by r.effective_from,r.id loop
    if not public.salary_rule_applies(rule_row,e,new.branch_id) then continue; end if;
    metric:=case rule_row.category when 'late_checkin' then new.late_minutes when 'early_checkout' then case when new.last_check_out_at is not null then new.shortfall_minutes else 0 end when 'absence' then case when new.status='absent' then 1 else 0 end when 'overtime' then new.overtime_minutes else 0 end;
    amount:=public.salary_rule_amount(rule_row,new.employee_id,metric,new.work_date,new.id);
    select * into existing from public.salary_ledger_transactions t where t.source_type='attendance' and t.source_id=new.id and t.rule_id=rule_row.id and t.reversal_of_id is null and t.status not in ('rejected','reversed') order by t.created_at desc limit 1;
    if amount=0 then
      if existing.id is not null and existing.status in ('pending','disputed') then update public.salary_ledger_transactions set status='reversed' where id=existing.id; insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note,actor_user_id) values(existing.organization_id,existing.id,'recalculated',existing.status,'reversed','Attendance was corrected; no charge remains.',null); end if;
      continue;
    end if;
    if existing.id is not null and existing.amount_minor=amount then continue; end if;
    if existing.id is not null then
      if existing.status in ('pending','disputed') then update public.salary_ledger_transactions set status='reversed' where id=existing.id;
      else
        insert into public.salary_ledger_transactions(organization_id,branch_id,employee_id,rule_id,reversal_of_id,transaction_type,category,label,description,amount_minor,status,occurred_at,work_date,source_type,source_id,created_by,approved_by,approved_at)
        values(existing.organization_id,existing.branch_id,existing.employee_id,existing.rule_id,existing.id,case when existing.transaction_type='deduction' then 'earning' else 'deduction' end,existing.category,'Reversal: '||existing.label,'Automatic reversal after attendance correction',existing.amount_minor,'approved',now(),new.work_date,'reversal',existing.id,null,null,now());
        update public.salary_ledger_transactions set status='reversed' where id=existing.id;
      end if;
    end if;
    description_text:=case rule_row.category when 'late_checkin' then greatest(0,new.late_minutes-rule_row.grace_minutes)||' chargeable late minute(s) on '||new.work_date when 'early_checkout' then greatest(0,new.shortfall_minutes-rule_row.grace_minutes)||' chargeable shortfall minute(s) on '||new.work_date when 'absence' then 'Absence recorded on '||new.work_date when 'overtime' then new.overtime_minutes||' overtime minute(s) on '||new.work_date else rule_row.name end;
    insert into public.salary_ledger_transactions(organization_id,branch_id,employee_id,rule_id,transaction_type,category,label,description,amount_minor,status,occurred_at,work_date,source_type,source_id,calculation_minutes,calculation_text,created_by,approved_by,approved_at)
    values(new.organization_id,new.branch_id,new.employee_id,rule_row.id,rule_row.transaction_type,rule_row.category,rule_row.name,description_text,amount,case when rule_row.approval_required then 'pending' else 'approved' end,now(),new.work_date,'attendance',new.id,metric::integer,description_text,null,case when not rule_row.approval_required then rule_row.created_by end,case when not rule_row.approval_required then now() end);
  end loop;
  return new;
end;
$$;

drop trigger if exists attendance_salary_ledger_materializer on public.attendance_daily;
create trigger attendance_salary_ledger_materializer after insert or update of first_check_in_at,last_check_out_at,status,late_minutes,overtime_minutes,shortfall_minutes on public.attendance_daily
for each row execute function public.materialize_attendance_salary_transactions();

create or replace function public.notify_salary_ledger_change()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare target_user uuid;
begin
  select user_id into target_user from public.employees where id=new.employee_id;
  if target_user is not null and (tg_op='INSERT' or new.status is distinct from old.status) then
    perform public.notify_user(new.organization_id,target_user,case when tg_op='INSERT' then 'Salary transaction added' else 'Salary transaction '||new.status end,new.label||': PKR '||to_char(new.amount_minor/100.0,'FM999G999G999D00'),'payroll','salary_transaction',new.id);
  end if;
  return new;
end;
$$;

create trigger salary_ledger_notification after insert or update of status on public.salary_ledger_transactions
for each row execute function public.notify_salary_ledger_change();
create trigger salary_ledger_realtime after insert or update on public.salary_ledger_transactions
for each row execute function public.publish_employee_hub_change();

alter table public.payroll_item_components drop constraint if exists payroll_item_components_source_check;
alter table public.payroll_item_components add constraint payroll_item_components_source_check
check(source in ('configured','attendance','leave','manual','system','statutory','loan','reimbursement','ledger'));

create or replace function public.release_salary_ledger_payroll_item()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  update public.salary_ledger_transactions set payroll_item_id=null,applied_at=null,status='approved'
  where payroll_item_id=old.id and status='applied';
  return old;
end;
$$;
create trigger release_salary_ledger_before_item_delete before delete on public.payroll_items
for each row execute function public.release_salary_ledger_payroll_item();

create or replace function public.apply_salary_ledger(p_run_id uuid)
returns integer language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare run_row public.payroll_runs%rowtype; item public.payroll_items%rowtype; entry public.salary_ledger_transactions%rowtype; applied integer:=0;
begin
  select * into run_row from public.payroll_runs where id=p_run_id for update;
  if run_row.id is null or run_row.status<>'draft' or not public.can_manage_payroll(run_row.organization_id) then raise exception 'draft payroll access required'; end if;
  for item in select * from public.payroll_items where payroll_run_id=run_row.id loop
    for entry in select * from public.salary_ledger_transactions t
      where t.employee_id=item.employee_id and t.status='approved' and t.payroll_item_id is null
        and coalesce(t.work_date,(t.occurred_at at time zone 'Asia/Karachi')::date) between run_row.period_start and run_row.period_end
        and (run_row.branch_id is null or t.branch_id is null or t.branch_id=run_row.branch_id)
      order by t.occurred_at,t.id for update
    loop
      insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source)
      values(item.id,entry.label,entry.transaction_type,entry.amount_minor,'ledger');
      update public.salary_ledger_transactions set payroll_item_id=item.id,status='applied',applied_at=now() where id=entry.id;
      insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note)
      values(entry.organization_id,entry.id,'applied','approved','applied','Applied to '||run_row.title);
      applied:=applied+1;
    end loop;
    update public.payroll_items pi set
      gross_minor=pi.prorated_base_minor+coalesce((select sum(amount_minor) from public.payroll_item_components where payroll_item_id=pi.id and component_type='earning'),0),
      deductions_minor=coalesce((select sum(amount_minor) from public.payroll_item_components where payroll_item_id=pi.id and component_type='deduction'),0)
      where pi.id=item.id;
    update public.payroll_items set net_minor=greatest(0,gross_minor-deductions_minor) where id=item.id;
  end loop;
  return applied;
end;
$$;

create or replace function public.sync_salary_payment_ledger()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare item public.payroll_items%rowtype; run_row public.payroll_runs%rowtype;
begin
  select * into item from public.payroll_items where id=new.payroll_item_id;
  select * into run_row from public.payroll_runs where id=item.payroll_run_id;
  insert into public.salary_ledger_transactions(organization_id,branch_id,employee_id,payroll_item_id,transaction_type,category,label,description,amount_minor,status,occurred_at,work_date,source_type,source_id,created_by,approved_by,approved_at,applied_at)
  values(new.organization_id,run_row.branch_id,item.employee_id,item.id,'payment','salary_payment','Salary payment',coalesce(nullif(trim(new.reference),''),'Salary payment recorded'),new.amount_minor,'paid',new.created_at,new.paid_on,'payment',new.id,new.recorded_by,new.recorded_by,new.created_at,new.created_at)
  on conflict do nothing;
  update public.salary_ledger_transactions set status='paid' where payroll_item_id=item.id and status='applied';
  return new;
end;
$$;
create trigger salary_payment_ledger after insert on public.salary_payments
for each row execute function public.sync_salary_payment_ledger();

alter table public.salary_transaction_rules enable row level security;
alter table public.salary_food_items enable row level security;
alter table public.salary_ledger_transactions enable row level security;
alter table public.salary_transaction_events enable row level security;
alter table public.salary_transaction_disputes enable row level security;

create policy salary_rules_read on public.salary_transaction_rules for select to authenticated using(public.can_manage_payroll(organization_id) or public.can_approve_payroll(organization_id));
create policy salary_rules_manage on public.salary_transaction_rules for all to authenticated using(public.can_manage_payroll(organization_id)) with check(public.can_manage_payroll(organization_id));
create policy salary_food_read on public.salary_food_items for select to authenticated using(public.can_manage_payroll(organization_id) or (branch_id is not null and public.can_manage_branch(branch_id)));
create policy salary_food_manage on public.salary_food_items for all to authenticated using(public.can_manage_payroll(organization_id)) with check(public.can_manage_payroll(organization_id));
create policy salary_ledger_read on public.salary_ledger_transactions for select to authenticated using(public.can_view_employee_salary(employee_id));
create policy salary_events_read on public.salary_transaction_events for select to authenticated using(exists(select 1 from public.salary_ledger_transactions t where t.id=transaction_id and public.can_view_employee_salary(t.employee_id)));
create policy salary_disputes_read on public.salary_transaction_disputes for select to authenticated using(public.can_view_employee_salary(employee_id));

grant select,insert,update,delete on public.salary_transaction_rules,public.salary_food_items to authenticated;
grant select on public.salary_ledger_transactions,public.salary_transaction_events,public.salary_transaction_disputes to authenticated;
revoke insert,update,delete on public.salary_ledger_transactions,public.salary_transaction_events,public.salary_transaction_disputes from authenticated;

revoke all on function public.can_view_employee_salary(uuid),public.salary_rule_applies(public.salary_transaction_rules,public.employees,uuid),public.salary_rule_amount(public.salary_transaction_rules,uuid,numeric,date,uuid),public.materialize_attendance_salary_transactions(),public.notify_salary_ledger_change(),public.release_salary_ledger_payroll_item(),public.sync_salary_payment_ledger() from public,anon,authenticated;
revoke all on function public.create_salary_transaction(uuid,uuid,uuid,text,text,text,text,bigint,timestamptz,date,text,uuid,numeric,bigint,integer,text),public.record_salary_food_charge(uuid,uuid,numeric,timestamptz,text),public.review_salary_transaction(uuid,text,text),public.dispute_salary_transaction(uuid,text),public.resolve_salary_dispute(uuid,text,text),public.reverse_salary_transaction(uuid,text),public.employee_salary_summary(uuid,date),public.salary_ledger_page(uuid,timestamptz,timestamptz,text,text,text,text,timestamptz,uuid,integer),public.apply_salary_ledger(uuid) from public,anon;
grant execute on function public.create_salary_transaction(uuid,uuid,uuid,text,text,text,text,bigint,timestamptz,date,text,uuid,numeric,bigint,integer,text),public.record_salary_food_charge(uuid,uuid,numeric,timestamptz,text),public.review_salary_transaction(uuid,text,text),public.dispute_salary_transaction(uuid,text),public.resolve_salary_dispute(uuid,text,text),public.reverse_salary_transaction(uuid,text),public.employee_salary_summary(uuid,date),public.salary_ledger_page(uuid,timestamptz,timestamptz,text,text,text,text,timestamptz,uuid,integer),public.apply_salary_ledger(uuid) to authenticated;

comment on table public.salary_ledger_transactions is 'Immutable-core, role-filtered employee salary ledger. Corrections use explicit reversals and all status changes are recorded as events.';
comment on function public.salary_ledger_page(uuid,timestamptz,timestamptz,text,text,text,text,timestamptz,uuid,integer) is 'Cursor-paginated employee salary history with date/time, type, category, status and search filters.';
