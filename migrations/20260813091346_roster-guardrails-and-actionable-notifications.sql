-- Roster validation, per-branch availability and actionable shift reminders.

alter table public.app_notifications drop constraint if exists app_notifications_category_check;
alter table public.app_notifications add constraint app_notifications_category_check
  check (category in ('attendance','leave','payroll','employee','security','system','shift','documents'));

alter table public.employee_availability
  drop constraint if exists employee_availability_employee_id_weekday_key;
alter table public.employee_availability
  add constraint employee_availability_employee_branch_weekday_key
  unique(employee_id,branch_id,weekday);

alter table public.trusted_devices alter column key_algorithm set default 'p256-keychain';
update public.trusted_devices
set key_algorithm='p256-keychain'
where key_algorithm='p256-secure-enclave';

create or replace function public.validate_roster_entry()
returns trigger language plpgsql
set search_path=pg_catalog,public,pg_temp as $$
declare
  employee_org uuid;
  branch_org uuid;
  availability_row public.employee_availability%rowtype;
  shift_start timestamp;
  shift_end timestamp;
  available_start timestamp;
  available_end timestamp;
begin
  select organization_id into employee_org from public.employees where id=new.employee_id;
  select organization_id into branch_org from public.branches where id=new.branch_id;
  if employee_org is null or branch_org is null or employee_org<>new.organization_id or branch_org<>new.organization_id then
    raise exception 'Employee and branch must belong to the same organization.';
  end if;

  if not exists(
    select 1 from public.employee_branch_assignments a
    where a.employee_id=new.employee_id and a.branch_id=new.branch_id
      and a.starts_on<=new.work_date and (a.ends_on is null or a.ends_on>=new.work_date)
  ) then
    raise exception 'Employee is not assigned to this branch on the selected date.';
  end if;

  if new.status<>'cancelled' and exists(
    select 1 from public.leave_requests l
    where l.employee_id=new.employee_id and l.status='approved'
      and new.work_date between l.start_date and l.end_date
  ) then
    raise exception 'Employee has approved leave on the selected date.';
  end if;

  select * into availability_row from public.employee_availability a
  where a.employee_id=new.employee_id and a.branch_id=new.branch_id
    and a.weekday=extract(isodow from new.work_date)::integer;
  if found then
    if not availability_row.is_available then
      raise exception 'Employee is unavailable on the selected weekday.';
    end if;
    shift_start=timestamp '2000-01-01'+new.starts_at;
    shift_end=timestamp '2000-01-01'+new.ends_at+case when new.ends_at<=new.starts_at then interval '1 day' else interval '0' end;
    available_start=timestamp '2000-01-01'+availability_row.available_from;
    available_end=timestamp '2000-01-01'+availability_row.available_until
      +case when availability_row.available_until<=availability_row.available_from then interval '1 day' else interval '0' end;
    if shift_start<available_start or shift_end>available_end then
      raise exception 'Shift falls outside the employee availability window.';
    end if;
  end if;

  if tg_op='UPDATE' and (
    new.employee_id is distinct from old.employee_id or new.work_date is distinct from old.work_date
    or new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at
    or new.break_minutes is distinct from old.break_minutes or new.notes is distinct from old.notes
  ) then
    new.is_published=false;new.published_at=null;new.published_by=null;
    if new.status='confirmed' then new.status='scheduled';end if;
  end if;
  return new;
end $$;

drop trigger if exists validate_roster_entry on public.shift_roster_entries;
create trigger validate_roster_entry
before insert or update on public.shift_roster_entries
for each row execute function public.validate_roster_entry();

create or replace function public.publish_roster(p_branch_id uuid,p_week_start date)
returns integer language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare
  published integer=0;
  roster_row public.shift_roster_entries%rowtype;
  employee_user uuid;
begin
  if not public.can_manage_branch(p_branch_id) then raise exception 'not permitted';end if;
  for roster_row in
    update public.shift_roster_entries
      set is_published=true,published_at=now(),published_by=auth.uid(),
          status=case when status='scheduled' then 'confirmed' else status end
    where branch_id=p_branch_id and work_date between p_week_start and p_week_start+6
      and status<>'cancelled' and not is_published
    returning *
  loop
    published=published+1;
    select user_id into employee_user from public.employees where id=roster_row.employee_id;
    if employee_user is not null then
      insert into public.app_notifications(organization_id,user_id,title,message,category,entity_type,entity_id)
      values(roster_row.organization_id,employee_user,'Roster published',
        'Your shift for '||to_char(roster_row.work_date,'Mon DD')||' is ready.','shift','shift_roster_entry',roster_row.id);
    end if;
  end loop;
  return published;
end $$;
