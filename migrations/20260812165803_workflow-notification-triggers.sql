create or replace function public.notify_leave_status_change()
returns trigger
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare target_user uuid;
begin
  if new.status is distinct from old.status and new.status in ('approved','rejected','cancelled') then
    select user_id into target_user from public.employees where id=new.employee_id;
    if target_user is not null then
      perform public.notify_user(new.organization_id,target_user,'Leave '||new.status,
        'Your leave request from '||new.start_date||' to '||new.end_date||' was '||new.status||'.',
        'leave','leave_request',new.id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists leave_status_notification on public.leave_requests;
create trigger leave_status_notification after update of status on public.leave_requests
for each row execute function public.notify_leave_status_change();

create or replace function public.notify_payroll_status_change()
returns trigger
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare row_item record;
begin
  if new.status is distinct from old.status and new.status in ('approved','locked') then
    for row_item in
      select e.user_id,i.id,i.net_minor from public.payroll_items i
      join public.employees e on e.id=i.employee_id
      where i.payroll_run_id=new.id and e.user_id is not null
    loop
      perform public.notify_user(new.organization_id,row_item.user_id,'Payslip ready',
        'Your '||new.title||' payslip is ready. Net salary: PKR '||to_char(row_item.net_minor/100.0,'FM999G999G999D00')||'.',
        'payroll','payroll_item',row_item.id);
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists payroll_status_notification on public.payroll_runs;
create trigger payroll_status_notification after update of status on public.payroll_runs
for each row execute function public.notify_payroll_status_change();

create or replace function public.notify_salary_payment()
returns trigger
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare target_user uuid; item_employee uuid;
begin
  select i.employee_id,e.user_id into item_employee,target_user
  from public.payroll_items i join public.employees e on e.id=i.employee_id
  where i.id=new.payroll_item_id;
  if target_user is not null then
    perform public.notify_user(new.organization_id,target_user,'Salary paid',
      'A salary payment of PKR '||to_char(new.amount_minor/100.0,'FM999G999G999D00')||' was recorded.',
      'payroll','payroll_item',new.payroll_item_id);
  end if;
  return new;
end;
$$;

drop trigger if exists salary_payment_notification on public.salary_payments;
create trigger salary_payment_notification after insert on public.salary_payments
for each row execute function public.notify_salary_payment();

revoke all on function public.notify_leave_status_change(),public.notify_payroll_status_change(),public.notify_salary_payment()
from public,anon,authenticated;
