-- Complete employee salary history: make pagination unambiguous and mirror every
-- non-ledger payroll component into the employee-visible, append-only ledger.

create unique index if not exists salary_ledger_external_source_unique
on public.salary_ledger_transactions(source_type,source_id)
where source_id is not null and source_type in ('payroll_component','payment');

create or replace function public.employee_salary_summary(p_employee_id uuid default null,p_as_of date default current_date)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
declare
  target_employee_id uuid;
  employee_row public.employees%rowtype;
  base bigint:=0;
  approved_earnings bigint:=0;
  approved_deductions bigint:=0;
  pending_deductions bigint:=0;
  paid bigint:=0;
  target_pay_day integer:=1;
  period_start date;
  period_end date;
  next_pay date;
  next_month_start date;
  next_month_end date;
begin
  target_employee_id:=p_employee_id;
  if target_employee_id is null then
    select e.id into target_employee_id from public.employees e where e.user_id=auth.uid() limit 1;
  end if;
  if target_employee_id is null or not public.can_view_employee_salary(target_employee_id) then raise exception 'not permitted'; end if;
  select e.* into employee_row from public.employees e where e.id=target_employee_id;
  period_start:=date_trunc('month',p_as_of)::date;
  period_end:=(date_trunc('month',p_as_of)+interval '1 month-1 day')::date;
  select coalesce(cv.base_salary_minor,0) into base
  from public.compensation_versions cv
  where cv.employee_id=employee_row.id and cv.effective_from<=p_as_of and (cv.effective_to is null or cv.effective_to>=p_as_of)
  order by cv.effective_from desc limit 1;
  select
    coalesce(sum(case when t.transaction_type='earning' then t.amount_minor else 0 end),0),
    coalesce(sum(case when t.transaction_type='deduction' then t.amount_minor else 0 end),0)
  into approved_earnings,approved_deductions
  from public.salary_ledger_transactions t
  where t.employee_id=employee_row.id and t.work_date between period_start and period_end and t.status in ('approved','applied','paid');
  select coalesce(sum(t.amount_minor),0) into pending_deductions
  from public.salary_ledger_transactions t
  where t.employee_id=employee_row.id and t.work_date between period_start and period_end
    and t.transaction_type='deduction' and t.status in ('pending','disputed');
  select coalesce(sum(sp.amount_minor),0) into paid
  from public.salary_payments sp
  join public.payroll_items pi on pi.id=sp.payroll_item_id
  where pi.employee_id=employee_row.id and sp.paid_on between period_start and period_end;
  select coalesce(pp.pay_day,1) into target_pay_day
  from public.employee_payroll_profiles pp
  where pp.employee_id=employee_row.id and pp.effective_from<=p_as_of and (pp.effective_to is null or pp.effective_to>=p_as_of)
  order by pp.effective_from desc limit 1;
  target_pay_day:=coalesce(target_pay_day,1);
  next_pay:=make_date(extract(year from p_as_of)::int,extract(month from p_as_of)::int,least(target_pay_day,extract(day from period_end)::int));
  if next_pay<p_as_of then
    next_month_start:=(date_trunc('month',p_as_of)+interval '1 month')::date;
    next_month_end:=(date_trunc('month',p_as_of)+interval '2 month-1 day')::date;
    next_pay:=next_month_start+(least(target_pay_day,extract(day from next_month_end)::int)-1);
  end if;
  return jsonb_build_object(
    'employeeId',employee_row.id,'currency','PKR','periodStart',period_start,'periodEnd',period_end,
    'baseSalaryMinor',base,'approvedEarningsMinor',approved_earnings,'approvedDeductionsMinor',approved_deductions,
    'pendingDeductionsMinor',pending_deductions,
    'estimatedNetMinor',greatest(0,base+approved_earnings-approved_deductions-pending_deductions),
    'confirmedNetMinor',greatest(0,base+approved_earnings-approved_deductions),
    'paidMinor',paid,'remainingMinor',greatest(0,base+approved_earnings-approved_deductions-paid),'nextPayDate',next_pay
  );
end;
$$;

create or replace function public.salary_ledger_page(
  p_employee_id uuid default null,p_from timestamptz default null,p_to timestamptz default null,
  p_transaction_type text default null,p_category text default null,p_status text default null,p_search text default null,
  p_before_at timestamptz default null,p_before_id uuid default null,p_limit integer default 20
)
returns table(id uuid,organization_id uuid,branch_id uuid,employee_id uuid,rule_id uuid,payroll_item_id uuid,reversal_of_id uuid,transaction_type text,category text,label text,description text,amount_minor bigint,currency char(3),status text,occurred_at timestamptz,work_date date,source_type text,source_id uuid,quantity numeric,unit_rate_minor bigint,calculation_minutes integer,calculation_text text,created_by uuid,approved_by uuid,approved_at timestamptz,applied_at timestamptz,created_at timestamptz,has_more boolean)
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare target_employee_id uuid; requested_limit integer:=least(greatest(p_limit,1),50);
begin
  target_employee_id:=p_employee_id;
  if target_employee_id is null then select e.id into target_employee_id from public.employees e where e.user_id=auth.uid() limit 1; end if;
  if target_employee_id is null or not public.can_view_employee_salary(target_employee_id) then raise exception 'not permitted'; end if;
  return query with filtered as(
    select t.* from public.salary_ledger_transactions t where t.employee_id=target_employee_id
      and (p_from is null or t.occurred_at>=p_from) and (p_to is null or t.occurred_at<=p_to)
      and (p_transaction_type is null or t.transaction_type=p_transaction_type)
      and (p_category is null or t.category=p_category) and (p_status is null or t.status=p_status)
      and (nullif(trim(p_search),'') is null or t.label ilike '%'||trim(p_search)||'%' or t.description ilike '%'||trim(p_search)||'%')
      and (p_before_at is null or (p_before_id is not null and (t.occurred_at,t.id)<(p_before_at,p_before_id)))
    order by t.occurred_at desc,t.id desc limit requested_limit+1
  )
  select f.id,f.organization_id,f.branch_id,f.employee_id,f.rule_id,f.payroll_item_id,f.reversal_of_id,f.transaction_type,f.category,f.label,f.description,f.amount_minor,f.currency,f.status,f.occurred_at,f.work_date,f.source_type,f.source_id,f.quantity,f.unit_rate_minor,f.calculation_minutes,f.calculation_text,f.created_by,f.approved_by,f.approved_at,f.applied_at,f.created_at,(select count(*)>requested_limit from filtered)
  from filtered f order by f.occurred_at desc,f.id desc limit requested_limit;
end;
$$;

create or replace function public.mirror_payroll_component_to_salary_ledger()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare
  item_row public.payroll_items%rowtype;
  run_row public.payroll_runs%rowtype;
  ledger_category text;
begin
  if new.source in ('ledger','system') then return new; end if;
  select pi.* into item_row from public.payroll_items pi where pi.id=new.payroll_item_id;
  select pr.* into run_row from public.payroll_runs pr where pr.id=item_row.payroll_run_id;
  ledger_category:=case
    when new.source='attendance' and lower(new.label) like '%late%' then 'late_checkin'
    when new.source='attendance' and lower(new.label) like '%early%' then 'early_checkout'
    when new.source='attendance' and lower(new.label) like '%overtime%' then 'overtime'
    when new.source='attendance' then 'absence'
    when new.source='leave' then 'unpaid_leave'
    when new.source='loan' then 'loan'
    when new.source='reimbursement' then 'reimbursement'
    when new.source='statutory' and lower(new.label) like '%eobi%' then 'eobi'
    when new.source='statutory' then 'tax'
    when new.source='configured' then case when new.component_type='earning' then 'allowance' else 'custom' end
    else 'custom'
  end;
  insert into public.salary_ledger_transactions(
    organization_id,branch_id,employee_id,payroll_item_id,transaction_type,category,label,description,
    amount_minor,status,occurred_at,work_date,source_type,source_id,created_by,approved_by,approved_at,applied_at
  ) values(
    run_row.organization_id,run_row.branch_id,item_row.employee_id,item_row.id,new.component_type,ledger_category,new.label,
    new.label||' included in '||run_row.title,new.amount_minor,'applied',new.created_at,run_row.period_end,
    'payroll_component',new.id,run_row.prepared_by,run_row.prepared_by,new.created_at,new.created_at
  ) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists mirror_payroll_component_salary_ledger on public.payroll_item_components;
create trigger mirror_payroll_component_salary_ledger
after insert on public.payroll_item_components
for each row execute function public.mirror_payroll_component_to_salary_ledger();

create or replace function public.release_salary_ledger_payroll_item()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  with released as (
    update public.salary_ledger_transactions
    set payroll_item_id=null,applied_at=null,
        status=case when source_type='payroll_component' then 'reversed' else 'approved' end
    where payroll_item_id=old.id and status in ('applied','paid')
    returning organization_id,id,source_type
  )
  insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note,actor_user_id)
  select organization_id,id,'payroll_recalculated','applied',case when source_type='payroll_component' then 'reversed' else 'approved' end,
         'Payroll draft was recalculated.',auth.uid()
  from released;
  return old;
end;
$$;

revoke all on function public.mirror_payroll_component_to_salary_ledger() from public,anon,authenticated;
comment on function public.mirror_payroll_component_to_salary_ledger() is 'Mirrors non-base, non-ledger payroll components into the employee salary history exactly once.';
