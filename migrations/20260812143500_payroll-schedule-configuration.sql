-- Payroll administrators need to maintain the effective work schedule used by
-- scheduled-working-day proration. The policies remain organization-scoped.
drop policy if exists schedules_manage on public.schedule_templates;
create policy schedules_manage on public.schedule_templates
for all to authenticated
using (
  public.has_org_role(organization_id, array['owner','super_admin','hr_admin'])
  or public.can_manage_payroll(organization_id)
  or (branch_id is not null and public.can_manage_branch(branch_id))
)
with check (
  public.has_org_role(organization_id, array['owner','super_admin','hr_admin'])
  or public.can_manage_payroll(organization_id)
  or (branch_id is not null and public.can_manage_branch(branch_id))
);

drop policy if exists employee_schedules_manage on public.employee_schedule_assignments;
create policy employee_schedules_manage on public.employee_schedule_assignments
for all to authenticated
using (
  exists (
    select 1
    from public.employees e
    where e.id = employee_schedule_assignments.employee_id
      and public.can_manage_payroll(e.organization_id)
  )
  or exists (
    select 1
    from public.employee_branch_assignments a
    where a.employee_id = employee_schedule_assignments.employee_id
      and public.can_manage_branch(a.branch_id)
  )
)
with check (
  exists (
    select 1
    from public.employees e
    where e.id = employee_schedule_assignments.employee_id
      and public.can_manage_payroll(e.organization_id)
  )
  or exists (
    select 1
    from public.employee_branch_assignments a
    where a.employee_id = employee_schedule_assignments.employee_id
      and public.can_manage_branch(a.branch_id)
  )
);
