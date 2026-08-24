revoke execute on all functions in schema public from public,anon;

grant execute on function public.is_org_member(uuid),public.has_org_role(uuid,text[]),public.is_branch_member(uuid),public.can_manage_branch(uuid),public.is_employee_self(uuid),public.can_manage_payroll(uuid),public.can_approve_payroll(uuid),public.can_access_employee_document(text,boolean) to authenticated;
grant execute on function public.bootstrap_organization(text,text,text),public.review_leave_request(uuid,text,text),public.prepare_payroll_run(uuid),public.transition_payroll_run(uuid,text),public.create_employee_invite(uuid,text,integer),public.claim_employee_invite(text),public.record_salary_payment(uuid,bigint,text,text,date) to authenticated;

revoke update on public.profiles from authenticated;
grant update(full_name,phone,avatar_path) on public.profiles to authenticated;

drop policy if exists branch_memberships_manage on public.branch_memberships;
create policy branch_memberships_manage on public.branch_memberships for all to authenticated
  using(exists(select 1 from public.branches b where b.id=branch_id and public.has_org_role(b.organization_id,array['owner','super_admin','hr_admin'])))
  with check(exists(select 1 from public.branches b where b.id=branch_id and public.has_org_role(b.organization_id,array['owner','super_admin','hr_admin'])));

drop policy if exists leave_requests_cancel_self on public.leave_requests;
revoke update on public.leave_requests from authenticated;

drop policy if exists payroll_runs_manage on public.payroll_runs;
create policy payroll_runs_insert on public.payroll_runs for insert to authenticated
  with check(public.can_manage_payroll(organization_id) and prepared_by=auth.uid() and status='draft' and approved_by is null);
revoke update,delete on public.payroll_runs from authenticated;
grant insert on public.payroll_runs to authenticated;

drop policy if exists payroll_items_manage on public.payroll_items;
revoke insert,update,delete on public.payroll_items from authenticated;
revoke insert,update,delete on public.payroll_item_components from authenticated;

create or replace function public.enforce_employee_organization()
returns trigger language plpgsql
set search_path=pg_catalog,public,pg_temp
as $$
begin
  if not exists(select 1 from public.employees e where e.id=new.employee_id and e.organization_id=new.organization_id) then
    raise exception 'employee does not belong to organization';
  end if;
  return new;
end;
$$;

create trigger attendance_attempts_employee_org before insert or update on public.attendance_attempts for each row when(new.employee_id is not null) execute function public.enforce_employee_organization();
create trigger attendance_events_employee_org before insert or update on public.attendance_events for each row execute function public.enforce_employee_organization();
create trigger attendance_daily_employee_org before insert or update on public.attendance_daily for each row execute function public.enforce_employee_organization();
create trigger attendance_overrides_employee_org before insert or update on public.attendance_overrides for each row execute function public.enforce_employee_organization();
create trigger leave_requests_employee_org before insert or update on public.leave_requests for each row execute function public.enforce_employee_organization();
create trigger leave_ledger_employee_org before insert or update on public.leave_balance_ledger for each row execute function public.enforce_employee_organization();
create trigger compensation_employee_org before insert or update on public.compensation_versions for each row execute function public.enforce_employee_organization();
create trigger payroll_adjustments_employee_org before insert or update on public.payroll_adjustments for each row execute function public.enforce_employee_organization();
create trigger payslip_employee_org before insert or update on public.payslip_documents for each row execute function public.enforce_employee_organization();

create or replace function public.protect_last_owner()
returns trigger language plpgsql
set search_path=pg_catalog,public,pg_temp
as $$
begin
  if old.role='owner' and old.is_active and (tg_op='DELETE' or new.role<>'owner' or not new.is_active) and not exists(
    select 1 from public.organization_memberships m where m.organization_id=old.organization_id and m.id<>old.id and m.role='owner' and m.is_active
  ) then raise exception 'organization must retain an active owner'; end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
create trigger organization_last_owner_guard before update or delete on public.organization_memberships for each row execute function public.protect_last_owner();

create index if not exists schedule_templates_branch_idx on public.schedule_templates(branch_id);
create index if not exists payslip_employee_idx on public.payslip_documents(employee_id);
create index if not exists compensation_organization_idx on public.compensation_versions(organization_id);
create index if not exists leave_ledger_organization_idx on public.leave_balance_ledger(organization_id);
create index if not exists leave_requests_organization_idx on public.leave_requests(organization_id);
create index if not exists payroll_runs_branch_idx on public.payroll_runs(branch_id);
create index if not exists payroll_items_compensation_idx on public.payroll_items(compensation_version_id);
create index if not exists salary_payments_organization_idx on public.salary_payments(organization_id);
create index if not exists audit_events_branch_idx on public.audit_events(branch_id);
create index if not exists biometric_employee_idx on public.biometric_enrollments(employee_id);
create index if not exists leave_requests_type_idx on public.leave_requests(leave_type_id);
create index if not exists leave_ledger_request_idx on public.leave_balance_ledger(leave_request_id);
create index if not exists payroll_items_run_idx on public.payroll_items(payroll_run_id);
