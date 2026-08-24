create index if not exists shift_swap_requested_by_idx on public.shift_swap_requests(requested_by_employee_id,status);
create index if not exists shift_swap_target_idx on public.shift_swap_requests(target_employee_id,status) where target_employee_id is not null;
create index if not exists shift_roster_org_idx on public.shift_roster_entries(organization_id);
create index if not exists employee_documents_org_idx on public.employee_documents(organization_id);
create index if not exists financial_profiles_org_idx on public.employee_financial_profiles(organization_id);
create index if not exists payroll_loans_org_idx on public.payroll_loans(organization_id);
create index if not exists reimbursements_org_idx on public.payroll_reimbursements(organization_id,status);
create index if not exists leave_blackouts_org_branch_idx on public.leave_blackout_periods(organization_id,branch_id,starts_on,ends_on);
