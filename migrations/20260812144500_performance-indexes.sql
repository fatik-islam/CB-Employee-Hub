-- Index every foreign-key and RLS lookup reported by the InsForge advisor.
-- These keep branch dashboards, policy checks, and payroll joins predictable as
-- employee and audit history grows.
create index if not exists attendance_attempts_branch_idx on public.attendance_attempts(branch_id);
create index if not exists attendance_attempts_employee_idx on public.attendance_attempts(employee_id);
create index if not exists attendance_attempts_org_idx on public.attendance_attempts(organization_id);
create index if not exists attendance_daily_org_idx on public.attendance_daily(organization_id);
create index if not exists attendance_events_branch_idx on public.attendance_events(branch_id);
create index if not exists attendance_events_org_idx on public.attendance_events(organization_id);
create index if not exists attendance_overrides_event_idx on public.attendance_overrides(attendance_event_id);
create index if not exists attendance_overrides_branch_idx on public.attendance_overrides(branch_id);
create index if not exists attendance_overrides_employee_idx on public.attendance_overrides(employee_id);
create index if not exists attendance_overrides_manager_idx on public.attendance_overrides(manager_user_id);
create index if not exists attendance_overrides_org_idx on public.attendance_overrides(organization_id);
create index if not exists audit_events_actor_idx on public.audit_events(actor_user_id);
create index if not exists branch_ip_rules_creator_idx on public.branch_ip_rules(created_by);
create index if not exists compensation_versions_approver_idx on public.compensation_versions(approved_by);
create index if not exists employee_invites_creator_idx on public.employee_invites(created_by);
create index if not exists employee_invites_employee_idx on public.employee_invites(employee_id);
create index if not exists employee_invites_org_idx on public.employee_invites(organization_id);
create index if not exists employee_invites_used_by_idx on public.employee_invites(used_by);
create index if not exists employee_salary_components_definition_idx on public.employee_salary_components(component_definition_id);
create index if not exists employee_schedule_template_idx on public.employee_schedule_assignments(schedule_template_id);
create index if not exists leave_balance_actor_idx on public.leave_balance_ledger(actor_user_id);
create index if not exists leave_balance_type_idx on public.leave_balance_ledger(leave_type_id);
create index if not exists leave_requests_reviewer_idx on public.leave_requests(reviewed_by);
create index if not exists payroll_adjustments_creator_idx on public.payroll_adjustments(created_by);
create index if not exists payroll_adjustments_employee_idx on public.payroll_adjustments(employee_id);
create index if not exists payroll_adjustments_org_idx on public.payroll_adjustments(organization_id);
create index if not exists payroll_adjustments_run_idx on public.payroll_adjustments(payroll_run_id);
create index if not exists payroll_item_components_definition_idx on public.payroll_item_components(component_definition_id);
create index if not exists payroll_item_components_item_idx on public.payroll_item_components(payroll_item_id);
create index if not exists payroll_runs_approver_idx on public.payroll_runs(approved_by);
create index if not exists payroll_runs_preparer_idx on public.payroll_runs(prepared_by);
create index if not exists payslip_documents_generator_idx on public.payslip_documents(generated_by);
create index if not exists payslip_documents_org_idx on public.payslip_documents(organization_id);
create index if not exists salary_payments_recorder_idx on public.salary_payments(recorded_by);
create index if not exists schedule_templates_org_idx on public.schedule_templates(organization_id);

create index if not exists leave_requests_end_idx on public.leave_requests(end_date);
create index if not exists payroll_runs_status_idx on public.payroll_runs(status);
create index if not exists profiles_active_idx on public.profiles(is_active);

-- Evaluate auth.uid() once per statement rather than once per row.
drop policy if exists attempts_select on public.attendance_attempts;
create policy attempts_select on public.attendance_attempts for select to authenticated
using (actor_user_id=(select auth.uid()) or public.is_employee_self(employee_id) or public.can_manage_branch(branch_id));

drop policy if exists branch_memberships_select on public.branch_memberships;
create policy branch_memberships_select on public.branch_memberships for select to authenticated
using (user_id=(select auth.uid()) or public.can_manage_branch(branch_id));

drop policy if exists org_memberships_select on public.organization_memberships;
create policy org_memberships_select on public.organization_memberships for select to authenticated
using (user_id=(select auth.uid()) or public.has_org_role(organization_id,array['owner','super_admin','hr_admin']));

drop policy if exists payroll_runs_insert on public.payroll_runs;
create policy payroll_runs_insert on public.payroll_runs for insert to authenticated
with check (public.can_manage_payroll(organization_id) and prepared_by=(select auth.uid()) and status='draft' and approved_by is null);

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles for insert to authenticated
with check (user_id=(select auth.uid()));

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using (
  user_id=(select auth.uid())
  or exists (
    select 1 from public.organization_memberships mine
    join public.organization_memberships theirs on theirs.organization_id=mine.organization_id
    where mine.user_id=(select auth.uid()) and mine.is_active
      and theirs.user_id=profiles.user_id and theirs.is_active
  )
);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
