create table public.employee_invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  email text not null,
  code_hash text not null unique,
  expires_at timestamptz not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  used_by uuid references auth.users(id) on delete restrict,
  used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index employee_invites_lookup_idx on public.employee_invites(code_hash) where used_at is null and revoked_at is null;

create or replace function public.create_employee_invite(p_employee_id uuid,p_email text,p_valid_hours integer default 72)
returns text
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare e public.employees%rowtype; invite_code text;
begin
  select * into e from public.employees where id=p_employee_id;
  if e.id is null then raise exception 'employee not found'; end if;
  if not public.has_org_role(e.organization_id,array['owner','super_admin','hr_admin']) then raise exception 'not permitted'; end if;
  if e.user_id is not null then raise exception 'employee already has an app account'; end if;
  if p_email is null or position('@' in p_email)=0 then raise exception 'valid email required'; end if;
  invite_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,10));
  update public.employee_invites set revoked_at=now() where employee_id=e.id and used_at is null and revoked_at is null;
  insert into public.employee_invites(organization_id,employee_id,email,code_hash,expires_at,created_by)
    values(e.organization_id,e.id,lower(trim(p_email)),encode(digest(invite_code,'sha256'),'hex'),now()+make_interval(hours=>greatest(1,least(p_valid_hours,168))),auth.uid());
  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(e.organization_id,auth.uid(),'employee.invited','employee',e.id,jsonb_build_object('expires_in_hours',greatest(1,least(p_valid_hours,168))));
  return invite_code;
end;
$$;

create or replace function public.claim_employee_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare invitation public.employee_invites%rowtype; caller_email text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  caller_email:=lower(coalesce(auth.jwt()->>'email',''));
  select * into invitation from public.employee_invites
    where code_hash=encode(digest(upper(trim(p_code)),'sha256'),'hex') and used_at is null and revoked_at is null and expires_at>now()
    for update;
  if invitation.id is null then raise exception 'invite is invalid or expired'; end if;
  if caller_email<>invitation.email then raise exception 'invite email does not match signed-in account'; end if;
  if exists(select 1 from public.organization_memberships where user_id=auth.uid()) then raise exception 'account is already assigned'; end if;
  update public.employees set user_id=auth.uid() where id=invitation.employee_id and user_id is null;
  if not found then raise exception 'employee account is already linked'; end if;
  insert into public.profiles(user_id,full_name)
    select auth.uid(),full_name from public.employees where id=invitation.employee_id on conflict(user_id) do nothing;
  insert into public.organization_memberships(organization_id,user_id,role) values(invitation.organization_id,auth.uid(),'employee');
  insert into public.branch_memberships(branch_id,user_id,role)
    select distinct a.branch_id,auth.uid(),'employee' from public.employee_branch_assignments a
    where a.employee_id=invitation.employee_id and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date)
    on conflict(branch_id,user_id) do update set is_active=true,role='employee';
  update public.employee_invites set used_by=auth.uid(),used_at=now() where id=invitation.id;
  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id)
    values(invitation.organization_id,auth.uid(),'employee.invite_claimed','employee',invitation.employee_id);
  return jsonb_build_object('organization_id',invitation.organization_id,'employee_id',invitation.employee_id);
end;
$$;

alter table public.employee_invites enable row level security;
create policy employee_invites_select on public.employee_invites for select to authenticated
  using(public.has_org_role(organization_id,array['owner','super_admin','hr_admin']));
grant select on public.employee_invites to authenticated;
revoke all on function public.create_employee_invite(uuid,text,integer),public.claim_employee_invite(text) from public,anon;
grant execute on function public.create_employee_invite(uuid,text,integer),public.claim_employee_invite(text) to authenticated;
