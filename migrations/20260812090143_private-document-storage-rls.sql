create or replace function public.can_access_employee_document(p_employee text,p_payroll boolean default false)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare employee_uuid uuid; org_uuid uuid;
begin
  employee_uuid:=p_employee::uuid;
  select organization_id into org_uuid from public.employees where id=employee_uuid;
  if org_uuid is null then return false; end if;
  if public.is_employee_self(employee_uuid) then return true; end if;
  if p_payroll then return public.has_org_role(org_uuid,array['owner','super_admin','payroll_admin','payroll_approver']); end if;
  return public.has_org_role(org_uuid,array['owner','super_admin','hr_admin']) or exists(
    select 1 from public.employee_branch_assignments a where a.employee_id=employee_uuid and public.can_manage_branch(a.branch_id)
  );
exception when invalid_text_representation then return false;
end;
$$;

alter table storage.objects enable row level security;
drop policy if exists storage_objects_owner_select on storage.objects;
drop policy if exists storage_objects_owner_insert on storage.objects;
drop policy if exists storage_objects_owner_update on storage.objects;
drop policy if exists storage_objects_owner_delete on storage.objects;

create policy cb_documents_select on storage.objects for select to authenticated using(
  (bucket='leave-documents' and public.can_access_employee_document((storage.foldername(key))[2],false)) or
  (bucket='payslips' and public.can_access_employee_document((storage.foldername(key))[2],true))
);
create policy cb_documents_insert on storage.objects for insert to authenticated with check(
  uploaded_by=(select auth.jwt()->>'sub') and (
    (bucket='leave-documents' and public.can_access_employee_document((storage.foldername(key))[2],false)) or
    (bucket='payslips' and public.can_access_employee_document((storage.foldername(key))[2],true))
  )
);
create policy cb_documents_update on storage.objects for update to authenticated
using(uploaded_by=(select auth.jwt()->>'sub'))
with check(uploaded_by=(select auth.jwt()->>'sub') and (
  (bucket='leave-documents' and public.can_access_employee_document((storage.foldername(key))[2],false)) or
  (bucket='payslips' and public.can_access_employee_document((storage.foldername(key))[2],true))
));
create policy cb_documents_delete on storage.objects for delete to authenticated using(
  uploaded_by=(select auth.jwt()->>'sub') and (
    (bucket='leave-documents' and public.can_access_employee_document((storage.foldername(key))[2],false)) or
    (bucket='payslips' and public.can_access_employee_document((storage.foldername(key))[2],true))
  )
);

grant usage on schema storage to authenticated;
grant select,insert,update,delete on storage.objects to authenticated;
