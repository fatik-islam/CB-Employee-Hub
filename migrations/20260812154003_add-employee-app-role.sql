alter table public.employees
  add column app_role text not null default 'employee'
  check (app_role in ('employee', 'manager'));

comment on column public.employees.app_role is
  'App access granted when the employee claims an invite; separate from job title.';

create or replace function public.sync_linked_employee_app_role()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.user_id is not null
     and (new.app_role is distinct from old.app_role or new.user_id is distinct from old.user_id) then
    update public.organization_memberships
    set role = new.app_role
    where organization_id = new.organization_id
      and user_id = new.user_id
      and role in ('employee', 'manager');

    update public.branch_memberships bm
    set role = new.app_role
    where bm.user_id = new.user_id
      and bm.role in ('employee', 'manager')
      and exists (
        select 1
        from public.employee_branch_assignments a
        where a.employee_id = new.id
          and a.branch_id = bm.branch_id
          and a.starts_on <= current_date
          and (a.ends_on is null or a.ends_on >= current_date)
      );

    if new.app_role is distinct from old.app_role then
      insert into public.audit_events(
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
      ) values (
        new.organization_id, auth.uid(), 'employee.app_role_changed', 'employee', new.id,
        jsonb_build_object('from', old.app_role, 'to', new.app_role)
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger employees_sync_linked_app_role
after update of app_role, user_id on public.employees
for each row execute function public.sync_linked_employee_app_role();

create or replace function public.claim_employee_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare
  invitation public.employee_invites%rowtype;
  employee_record public.employees%rowtype;
  caller_email text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  caller_email:=lower(coalesce(auth.jwt()->>'email',''));
  select * into invitation from public.employee_invites
    where code_hash=encode(digest(upper(trim(p_code)),'sha256'),'hex')
      and used_at is null and revoked_at is null and expires_at>now()
    for update;
  if invitation.id is null then raise exception 'invite is invalid or expired'; end if;
  if caller_email<>invitation.email then raise exception 'invite email does not match signed-in account'; end if;
  if exists(select 1 from public.organization_memberships where user_id=auth.uid()) then raise exception 'account is already assigned'; end if;

  update public.employees
  set user_id=auth.uid()
  where id=invitation.employee_id and user_id is null
  returning * into employee_record;
  if employee_record.id is null then raise exception 'employee account is already linked'; end if;

  insert into public.profiles(user_id,full_name)
    values(auth.uid(), employee_record.full_name)
    on conflict(user_id) do nothing;
  insert into public.organization_memberships(organization_id,user_id,role)
    values(invitation.organization_id,auth.uid(),employee_record.app_role);
  insert into public.branch_memberships(branch_id,user_id,role)
    select distinct a.branch_id,auth.uid(),employee_record.app_role
    from public.employee_branch_assignments a
    where a.employee_id=invitation.employee_id
      and a.starts_on<=current_date
      and (a.ends_on is null or a.ends_on>=current_date)
    on conflict(branch_id,user_id)
    do update set is_active=true,role=excluded.role;

  update public.employee_invites set used_by=auth.uid(),used_at=now() where id=invitation.id;
  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(
      invitation.organization_id,auth.uid(),'employee.invite_claimed','employee',invitation.employee_id,
      jsonb_build_object('app_role', employee_record.app_role)
    );
  return jsonb_build_object(
    'organization_id',invitation.organization_id,
    'employee_id',invitation.employee_id,
    'app_role',employee_record.app_role
  );
end;
$$;

revoke all on function public.claim_employee_invite(text) from public, anon;
grant execute on function public.claim_employee_invite(text) to authenticated;
