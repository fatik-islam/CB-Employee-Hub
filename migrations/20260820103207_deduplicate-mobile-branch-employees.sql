-- A worker can have historical or accidentally overlapping assignment rows for
-- one branch. Use EXISTS instead of a direct join so the mobile employee page
-- always returns one row per employee and remains stable for attendance views.
create or replace function public.mobile_branch_employees(
  p_branch_id uuid,
  p_limit integer default 100,
  p_offset integer default 0
)
returns setof public.employees
language sql
stable
security definer
set search_path=pg_catalog,public,pg_temp
as $$
  select e.*
  from public.employees e
  where exists (
    select 1
    from public.employee_branch_assignments a
    where a.employee_id=e.id
      and a.branch_id=p_branch_id
      and a.starts_on<=current_date
      and (a.ends_on is null or a.ends_on>=current_date)
  )
    and (
      public.can_manage_branch(p_branch_id)
      or e.user_id=auth.uid()
      or exists (
        select 1
        from public.branches b
        where b.id=p_branch_id
          and public.has_org_role(
            b.organization_id,
            array['owner','super_admin','hr_admin','payroll_admin','payroll_approver']
          )
      )
    )
  order by e.full_name,e.id
  limit least(greatest(p_limit,1),100)
  offset greatest(p_offset,0);
$$;

revoke all on function public.mobile_branch_employees(uuid,integer,integer) from public,anon;
grant execute on function public.mobile_branch_employees(uuid,integer,integer) to authenticated;

-- Count unique employees as well, otherwise overlapping assignments inflate the
-- dashboard even though the attendance register correctly shows one person.
create or replace function public.mobile_dashboard_summary(p_branch_id uuid,p_date date)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,public,pg_temp
as $$
  select jsonb_build_object(
    'activeEmployees',(
      select count(distinct e.id)
      from public.employee_branch_assignments a
      join public.employees e on e.id=a.employee_id
      where a.branch_id=p_branch_id
        and e.employment_status='active'
        and a.starts_on<=p_date
        and (a.ends_on is null or a.ends_on>=p_date)
    ),
    'present',(select count(*) from public.attendance_daily where branch_id=p_branch_id and work_date=p_date and status='present'),
    'absent',(select count(*) from public.attendance_daily where branch_id=p_branch_id and work_date=p_date and status='absent'),
    'onLeave',(select count(*) from public.attendance_daily where branch_id=p_branch_id and work_date=p_date and status='leave'),
    'pendingCorrections',(select count(*) from public.attendance_correction_requests where branch_id=p_branch_id and status='pending'),
    'scheduledShifts',(select count(*) from public.shift_roster_entries where branch_id=p_branch_id and work_date=p_date and status<>'cancelled')
  )
  where public.can_manage_branch(p_branch_id)
    or exists(
      select 1
      from public.employee_branch_assignments a
      join public.employees e on e.id=a.employee_id
      where a.branch_id=p_branch_id and e.user_id=auth.uid()
    )
    or exists(
      select 1
      from public.branches b
      where b.id=p_branch_id
        and public.has_org_role(
          b.organization_id,
          array['owner','super_admin','hr_admin','payroll_admin','payroll_approver']
        )
    );
$$;

revoke all on function public.mobile_dashboard_summary(uuid,date) from public,anon;
grant execute on function public.mobile_dashboard_summary(uuid,date) to authenticated;
