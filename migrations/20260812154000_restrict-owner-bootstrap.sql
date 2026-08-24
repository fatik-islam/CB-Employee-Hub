-- Allow only the designated, verified owner email to claim the seeded
-- organization. The email is represented only by its normalized SHA-256 hash.
create or replace function public.bootstrap_organization(org_name text, branch_name text, branch_code text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare
  target_org uuid;
  target_branch uuid;
  caller_name text;
  caller_email text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  caller_email := lower(trim(coalesce(auth.jwt()->>'email','')));
  if encode(public.digest(caller_email,'sha256'),'hex') <> 'a0c8d35221bb56ef2ab1f2a7f959dc8d96615f5d90ec8849a72bff64401a353f' then
    raise exception 'this account is not authorized to claim the owner role';
  end if;

  if exists(select 1 from public.organization_memberships where user_id=auth.uid()) then
    raise exception 'user already belongs to an organization';
  end if;

  select id into target_org
  from public.organizations
  where not exists(
    select 1 from public.organization_memberships m
    where m.organization_id=organizations.id and m.is_active
  )
  order by created_at
  limit 1
  for update;

  if target_org is null then raise exception 'initial organization already claimed'; end if;

  select id into target_branch
  from public.branches
  where organization_id=target_org and is_active
  order by created_at
  limit 1;

  if target_branch is null then raise exception 'initial branch is not available'; end if;

  caller_name:=coalesce(nullif(trim(auth.jwt()->>'name'),''),nullif(split_part(caller_email,'@',1),''),'Owner');
  insert into public.profiles(user_id,full_name) values(auth.uid(),caller_name) on conflict(user_id) do nothing;
  insert into public.organization_memberships(organization_id,user_id,role) values(target_org,auth.uid(),'owner');
  insert into public.branch_memberships(branch_id,user_id,role,can_override_attendance) values(target_branch,auth.uid(),'branch_admin',true);
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(target_org,target_branch,auth.uid(),'organization.claimed','organization',target_org,jsonb_build_object('bootstrap_email_hash_verified',true));

  return jsonb_build_object('organization_id',target_org,'branch_id',target_branch);
end;
$$;

revoke all on function public.bootstrap_organization(text,text,text) from public,anon;
grant execute on function public.bootstrap_organization(text,text,text) to authenticated;
