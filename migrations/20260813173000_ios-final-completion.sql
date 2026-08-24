-- Final iOS completion: account-deletion workflow, device cleanup, split shifts,
-- and dynamic statutory payroll rules.

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null,
  requested_by_email text,
  reason text not null check (length(trim(reason)) between 5 and 500),
  status text not null default 'pending' check (status in ('pending','processing','completed','rejected')),
  purge_after timestamptz not null default (now() + interval '30 days'),
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  processor_note text
);

create unique index if not exists account_deletion_one_open_request
  on public.account_deletion_requests(user_id)
  where status in ('pending','processing');
create index if not exists account_deletion_due_idx
  on public.account_deletion_requests(status,purge_after);

alter table public.account_deletion_requests enable row level security;
drop policy if exists account_deletion_own_read on public.account_deletion_requests;
create policy account_deletion_own_read on public.account_deletion_requests
  for select to authenticated using(user_id=(select auth.uid()));
revoke insert,update,delete on public.account_deletion_requests from authenticated;
grant select on public.account_deletion_requests to authenticated;

create or replace function public.request_account_deletion(p_reason text)
returns uuid
language plpgsql security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare
  membership public.organization_memberships%rowtype;
  owner_count integer;
  employee_row public.employees%rowtype;
  request_id uuid;
  actor_email text;
begin
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason is required'; end if;
  select * into membership from public.organization_memberships
    where user_id=auth.uid() and is_active order by created_at limit 1 for update;
  if membership.id is null then raise exception 'active account not found'; end if;
  if membership.role='owner' then
    select count(*) into owner_count from public.organization_memberships
      where organization_id=membership.organization_id and role='owner' and is_active;
    if owner_count<=1 then raise exception 'assign another owner before deleting this account'; end if;
  end if;

  select * into employee_row from public.employees
    where organization_id=membership.organization_id and user_id=auth.uid() limit 1;
  select email into actor_email from auth.users where id=auth.uid();

  insert into public.account_deletion_requests(organization_id,user_id,requested_by_email,reason)
  values(membership.organization_id,auth.uid(),actor_email,trim(p_reason))
  on conflict (user_id) where status in ('pending','processing')
  do update set reason=excluded.reason,requested_at=now(),purge_after=now()+interval '30 days'
  returning id into request_id;

  update public.mobile_push_tokens set is_active=false where user_id=auth.uid();
  update public.trusted_devices set is_active=false,revoked_at=now()
    where user_id=auth.uid() and is_active;
  if employee_row.id is not null then
    update public.employee_face_templates
      set revoked_at=coalesce(revoked_at,now()),revoked_by=coalesce(revoked_by,auth.uid()),
          revocation_reason=coalesce(revocation_reason,'Account deletion requested')
      where employee_id=employee_row.id and revoked_at is null;
    update public.employees set employment_status='inactive',user_id=null where id=employee_row.id;
  end if;
  update public.branch_memberships set is_active=false where user_id=auth.uid();
  update public.organization_memberships set is_active=false where user_id=auth.uid();

  insert into public.audit_events(organization_id,actor_user_id,action,entity_type,entity_id,reason,metadata)
  values(membership.organization_id,auth.uid(),'account.deletion_requested','user',auth.uid(),trim(p_reason),
    jsonb_build_object('request_id',request_id,'purge_after',now()+interval '30 days'));
  return request_id;
end;
$$;

revoke all on function public.request_account_deletion(text) from public,anon;
grant execute on function public.request_account_deletion(text) to authenticated;

create or replace function public.deactivate_my_mobile_device(p_device_id text)
returns boolean language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
begin
  update public.mobile_push_tokens set is_active=false
    where user_id=auth.uid() and device_id=p_device_id;
  return found;
end $$;
revoke all on function public.deactivate_my_mobile_device(text) from public,anon;
grant execute on function public.deactivate_my_mobile_device(text) to authenticated;

alter table public.shift_roster_entries
  drop constraint if exists shift_roster_entries_employee_id_work_date_key;
create unique index if not exists shift_roster_employee_date_start_key
  on public.shift_roster_entries(employee_id,work_date,starts_at)
  where status<>'cancelled';

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
  if not exists(select 1 from public.employee_branch_assignments a where a.employee_id=new.employee_id and a.branch_id=new.branch_id and a.starts_on<=new.work_date and (a.ends_on is null or a.ends_on>=new.work_date)) then
    raise exception 'Employee is not assigned to this branch on the selected date.';
  end if;
  if new.status<>'cancelled' and exists(select 1 from public.leave_requests l where l.employee_id=new.employee_id and l.status='approved' and new.work_date between l.start_date and l.end_date) then
    raise exception 'Employee has approved leave on the selected date.';
  end if;

  shift_start=new.work_date+new.starts_at;
  shift_end=new.work_date+new.ends_at+case when new.ends_at<=new.starts_at then interval '1 day' else interval '0' end;
  if new.status<>'cancelled' and exists(
    select 1 from public.shift_roster_entries r
    where r.employee_id=new.employee_id and r.id<>new.id and r.status<>'cancelled'
      and tsrange(r.work_date+r.starts_at,
        r.work_date+r.ends_at+case when r.ends_at<=r.starts_at then interval '1 day' else interval '0' end,'[)')
        && tsrange(shift_start,shift_end,'[)')
  ) then raise exception 'This shift overlaps another shift for the employee.'; end if;

  select * into availability_row from public.employee_availability a
    where a.employee_id=new.employee_id and a.branch_id=new.branch_id and a.weekday=extract(isodow from new.work_date)::integer;
  if found then
    if not availability_row.is_available then raise exception 'Employee is unavailable on the selected weekday.'; end if;
    available_start=new.work_date+availability_row.available_from;
    available_end=new.work_date+availability_row.available_until+case when availability_row.available_until<=availability_row.available_from then interval '1 day' else interval '0' end;
    if shift_start<available_start or shift_end>available_end then raise exception 'Shift falls outside the employee availability window.'; end if;
  end if;
  if tg_op='UPDATE' and (new.employee_id is distinct from old.employee_id or new.work_date is distinct from old.work_date or new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at or new.break_minutes is distinct from old.break_minutes or new.notes is distinct from old.notes) then
    new.is_published=false;new.published_at=null;new.published_by=null;
    if new.status='confirmed' then new.status='scheduled';end if;
  end if;
  return new;
end $$;

create table if not exists public.payroll_statutory_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  rule_type text not null check(rule_type in ('fixed_deduction','percentage_deduction','income_tax_brackets')),
  configuration jsonb not null default '{}'::jsonb,
  effective_from date not null,
  effective_to date,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,code,effective_from),
  check(effective_to is null or effective_to>=effective_from)
);
create index if not exists payroll_statutory_rules_active_idx on public.payroll_statutory_rules(organization_id,effective_from desc) where is_active;
alter table public.payroll_statutory_rules enable row level security;
drop policy if exists payroll_statutory_rules_read on public.payroll_statutory_rules;
create policy payroll_statutory_rules_read on public.payroll_statutory_rules for select to authenticated using(public.is_org_member(organization_id));
drop policy if exists payroll_statutory_rules_manage on public.payroll_statutory_rules;
create policy payroll_statutory_rules_manage on public.payroll_statutory_rules for all to authenticated using(public.can_manage_payroll(organization_id)) with check(public.can_manage_payroll(organization_id));
grant select,insert,update,delete on public.payroll_statutory_rules to authenticated;

create or replace function public.apply_statutory_rules(p_run_id uuid)
returns integer language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare
  run_row public.payroll_runs%rowtype;
  item public.payroll_items%rowtype;
  rule public.payroll_statutory_rules%rowtype;
  bracket jsonb;
  amount bigint;
  applied integer:=0;
begin
  select * into run_row from public.payroll_runs where id=p_run_id for update;
  if run_row.id is null or run_row.status<>'draft' or not public.can_manage_payroll(run_row.organization_id) then raise exception 'draft payroll access required';end if;
  for item in select * from public.payroll_items where payroll_run_id=run_row.id loop
    for rule in select * from public.payroll_statutory_rules
      where organization_id=run_row.organization_id and is_active and effective_from<=run_row.period_end
        and (effective_to is null or effective_to>=run_row.period_start)
      order by effective_from,code
    loop
      amount:=0;
      if rule.rule_type='fixed_deduction' then
        amount:=greatest(0,coalesce((rule.configuration->>'amount_minor')::bigint,0));
      elsif rule.rule_type='percentage_deduction' then
        amount:=greatest(0,round(item.gross_minor*coalesce((rule.configuration->>'rate_percent')::numeric,0)/100)::bigint);
      elsif rule.rule_type='income_tax_brackets' then
        select value into bracket from jsonb_array_elements(coalesce(rule.configuration->'brackets','[]'::jsonb))
          where value->>'up_to_minor' is null or item.gross_minor<=(value->>'up_to_minor')::bigint
          order by coalesce((value->>'up_to_minor')::bigint,9223372036854775807) limit 1;
        if bracket is not null then
          amount:=greatest(0,coalesce((bracket->>'base_minor')::bigint,0)+round(greatest(0,item.gross_minor-coalesce((bracket->>'over_minor')::bigint,0))*coalesce((bracket->>'rate_percent')::numeric,0)/100)::bigint);
        end if;
      end if;
      if amount>0 and not exists(select 1 from public.payroll_item_components where payroll_item_id=item.id and source='statutory' and label=rule.name) then
        insert into public.payroll_item_components(payroll_item_id,label,component_type,amount_minor,source)
          values(item.id,rule.name,'deduction',amount,'statutory');
        applied:=applied+1;
      end if;
    end loop;
    update public.payroll_items pi set
      deductions_minor=coalesce((select sum(amount_minor) from public.payroll_item_components where payroll_item_id=pi.id and component_type='deduction'),0)
      where pi.id=item.id;
    update public.payroll_items set net_minor=greatest(0,gross_minor-deductions_minor) where id=item.id;
  end loop;
  return applied;
end $$;
revoke all on function public.apply_statutory_rules(uuid) from public,anon;
grant execute on function public.apply_statutory_rules(uuid) to authenticated;

create or replace function public.bulk_copy_roster(p_branch_id uuid,p_source_start date,p_target_start date)
returns integer language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare copied integer;
begin
  if not public.can_manage_branch(p_branch_id) then raise exception 'not permitted';end if;
  insert into public.shift_roster_entries(organization_id,branch_id,employee_id,work_date,starts_at,ends_at,break_minutes,status,notes,created_by,is_published)
  select organization_id,branch_id,employee_id,p_target_start+(work_date-p_source_start),starts_at,ends_at,break_minutes,'scheduled',notes,auth.uid(),false
  from public.shift_roster_entries where branch_id=p_branch_id and work_date between p_source_start and p_source_start+6 and status<>'cancelled'
  on conflict(employee_id,work_date,starts_at) where status<>'cancelled'
  do update set ends_at=excluded.ends_at,break_minutes=excluded.break_minutes,status='scheduled',notes=excluded.notes,is_published=false,published_at=null,published_by=null;
  get diagnostics copied=row_count;return copied;
end $$;

comment on table public.account_deletion_requests is 'In-app permanent account deletion queue. Operational access is disabled immediately; legally required payroll and audit records are retained under policy.';
comment on table public.payroll_statutory_rules is 'Effective-dated organization rules. Legal values are configured by authorized payroll staff and are never hardcoded in the mobile build.';
