create extension if not exists pgcrypto;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  default_currency char(3) not null default 'PKR',
  timezone text not null default 'Asia/Karachi',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 2 and 120),
  phone text,
  avatar_path text,
  is_active boolean not null default true,
  last_reauthenticated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','super_admin','hr_admin','payroll_admin','payroll_approver','manager','employee')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  code text not null,
  name text not null check (length(trim(name)) between 2 and 120),
  address text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  geofence_radius_m integer not null default 50 check (geofence_radius_m between 10 and 1000),
  attendance_verification_mode text not null default 'IP_OR_GPS' check (attendance_verification_mode in ('IP_ONLY','GPS_ONLY','IP_OR_GPS','IP_AND_GPS')),
  requires_biometric boolean not null default true,
  gps_accuracy_limit_m integer not null default 50 check (gps_accuracy_limit_m between 5 and 500),
  timezone text not null default 'Asia/Karachi',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code),
  check ((latitude is null and longitude is null) or (latitude between -90 and 90 and longitude between -180 and 180))
);

create table public.branch_memberships (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('branch_admin','manager','employee')),
  can_override_attendance boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, user_id)
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid unique references auth.users(id) on delete set null,
  employee_code text not null,
  full_name text not null check (length(trim(full_name)) between 2 and 120),
  phone text,
  cnic text,
  address text,
  position text,
  joining_date date not null,
  employment_status text not null default 'active' check (employment_status in ('invited','active','inactive','terminated')),
  termination_date date,
  legacy_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, employee_code),
  unique (organization_id, cnic),
  check (termination_date is null or termination_date >= joining_date)
);

create table public.employee_branch_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  is_primary boolean not null default false,
  starts_on date not null,
  ends_on date,
  created_at timestamptz not null default now(),
  unique (employee_id, branch_id, starts_on),
  check (ends_on is null or ends_on >= starts_on)
);

create unique index employee_one_current_primary_branch
  on public.employee_branch_assignments(employee_id)
  where is_primary and ends_on is null;

create table public.branch_ip_rules (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  label text not null,
  network inet not null,
  is_active boolean not null default true,
  valid_from timestamptz,
  valid_until timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, network),
  check (valid_until is null or valid_from is null or valid_until > valid_from)
);

create table public.schedule_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  name text not null,
  weekly_rules jsonb not null default '{}'::jsonb,
  grace_minutes integer not null default 0 check (grace_minutes between 0 and 240),
  expected_minutes_per_day integer not null default 480 check (expected_minutes_per_day between 1 and 1440),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.employee_schedule_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  schedule_template_id uuid not null references public.schedule_templates(id) on delete restrict,
  effective_from date not null,
  effective_to date,
  created_at timestamptz not null default now(),
  unique (employee_id, effective_from),
  check (effective_to is null or effective_to >= effective_from)
);

create table public.app_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  leave_year_start_month smallint not null default 1 check (leave_year_start_month between 1 and 12),
  payroll_proration_method text not null default 'eligible_scheduled_working_days' check (payroll_proration_method in ('eligible_scheduled_working_days')),
  require_manager_reauth_minutes integer not null default 10 check (require_manager_reauth_minutes between 1 and 60),
  updated_at timestamptz not null default now()
);

create index organization_memberships_user_idx on public.organization_memberships(user_id) where is_active;
create index branches_organization_idx on public.branches(organization_id) where is_active;
create index branch_memberships_user_idx on public.branch_memberships(user_id) where is_active;
create index employee_assignments_branch_idx on public.employee_branch_assignments(branch_id, starts_on, ends_on);
create index employees_org_status_idx on public.employees(organization_id, employment_status);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger organizations_updated_at before update on public.organizations for each row execute function public.set_updated_at();
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger organization_memberships_updated_at before update on public.organization_memberships for each row execute function public.set_updated_at();
create trigger branches_updated_at before update on public.branches for each row execute function public.set_updated_at();
create trigger branch_memberships_updated_at before update on public.branch_memberships for each row execute function public.set_updated_at();
create trigger employees_updated_at before update on public.employees for each row execute function public.set_updated_at();
create trigger branch_ip_rules_updated_at before update on public.branch_ip_rules for each row execute function public.set_updated_at();
create trigger schedule_templates_updated_at before update on public.schedule_templates for each row execute function public.set_updated_at();

create or replace function public.is_org_member(target_org uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1 from public.organization_memberships m
    where m.organization_id = target_org and m.user_id = auth.uid() and m.is_active
  );
$$;

create or replace function public.has_org_role(target_org uuid, allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1 from public.organization_memberships m
    where m.organization_id = target_org and m.user_id = auth.uid() and m.is_active and m.role = any(allowed_roles)
  );
$$;

create or replace function public.is_branch_member(target_branch uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1 from public.branch_memberships bm
    where bm.branch_id = target_branch and bm.user_id = auth.uid() and bm.is_active
  ) or exists (
    select 1 from public.branches b
    where b.id = target_branch and public.has_org_role(b.organization_id, array['owner','super_admin','hr_admin','payroll_admin','payroll_approver'])
  );
$$;

create or replace function public.can_manage_branch(target_branch uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1 from public.branch_memberships bm
    where bm.branch_id = target_branch and bm.user_id = auth.uid() and bm.is_active and bm.role in ('branch_admin','manager')
  ) or exists (
    select 1 from public.branches b
    where b.id = target_branch and public.has_org_role(b.organization_id, array['owner','super_admin','hr_admin'])
  );
$$;

create or replace function public.is_employee_self(target_employee uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (select 1 from public.employees e where e.id = target_employee and e.user_id = auth.uid());
$$;

create or replace function public.bootstrap_organization(org_name text, branch_name text, branch_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  new_org uuid;
  new_branch uuid;
  caller_name text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if exists (select 1 from public.organization_memberships where user_id = auth.uid()) then raise exception 'user already belongs to an organization'; end if;
  if exists (select 1 from public.organizations) then raise exception 'initial organization already exists'; end if;
  caller_name := coalesce(nullif(trim(auth.jwt()->>'name'), ''), nullif(split_part(auth.jwt()->>'email','@',1), ''), 'Owner');
  insert into public.organizations(name) values (trim(org_name)) returning id into new_org;
  insert into public.profiles(user_id, full_name) values (auth.uid(), caller_name) on conflict (user_id) do nothing;
  insert into public.organization_memberships(organization_id, user_id, role) values (new_org, auth.uid(), 'owner');
  insert into public.branches(organization_id, name, code) values (new_org, trim(branch_name), upper(trim(branch_code))) returning id into new_branch;
  insert into public.branch_memberships(branch_id, user_id, role, can_override_attendance) values (new_branch, auth.uid(), 'branch_admin', true);
  insert into public.app_settings(organization_id) values (new_org);
  return jsonb_build_object('organization_id', new_org, 'branch_id', new_branch);
end;
$$;

revoke all on function public.bootstrap_organization(text,text,text) from public;
grant execute on function public.bootstrap_organization(text,text,text) to authenticated;

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.branches enable row level security;
alter table public.branch_memberships enable row level security;
alter table public.employees enable row level security;
alter table public.employee_branch_assignments enable row level security;
alter table public.branch_ip_rules enable row level security;
alter table public.schedule_templates enable row level security;
alter table public.employee_schedule_assignments enable row level security;
alter table public.app_settings enable row level security;

create policy organizations_select on public.organizations for select to authenticated using (public.is_org_member(id));
create policy organizations_update on public.organizations for update to authenticated using (public.has_org_role(id, array['owner','super_admin'])) with check (public.has_org_role(id, array['owner','super_admin']));
create policy profiles_select on public.profiles for select to authenticated using (user_id = auth.uid() or exists (select 1 from public.organization_memberships mine join public.organization_memberships theirs on theirs.organization_id = mine.organization_id where mine.user_id = auth.uid() and mine.is_active and theirs.user_id = profiles.user_id and theirs.is_active));
create policy profiles_insert_self on public.profiles for insert to authenticated with check (user_id = auth.uid());
create policy profiles_update_self on public.profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy org_memberships_select on public.organization_memberships for select to authenticated using (user_id = auth.uid() or public.has_org_role(organization_id, array['owner','super_admin','hr_admin']));
create policy org_memberships_manage on public.organization_memberships for all to authenticated using (public.has_org_role(organization_id, array['owner','super_admin'])) with check (public.has_org_role(organization_id, array['owner','super_admin']));
create policy branches_select on public.branches for select to authenticated using (public.is_org_member(organization_id));
create policy branches_manage on public.branches for all to authenticated using (public.has_org_role(organization_id, array['owner','super_admin'])) with check (public.has_org_role(organization_id, array['owner','super_admin']));
create policy branch_memberships_select on public.branch_memberships for select to authenticated using (user_id = auth.uid() or public.can_manage_branch(branch_id));
create policy branch_memberships_manage on public.branch_memberships for all to authenticated using (public.can_manage_branch(branch_id)) with check (public.can_manage_branch(branch_id));
create policy employees_select on public.employees for select to authenticated using (public.is_employee_self(id) or public.has_org_role(organization_id, array['owner','super_admin','hr_admin','payroll_admin','payroll_approver']) or exists (select 1 from public.employee_branch_assignments a where a.employee_id = employees.id and public.can_manage_branch(a.branch_id)));
create policy employees_manage on public.employees for all to authenticated using (public.has_org_role(organization_id, array['owner','super_admin','hr_admin'])) with check (public.has_org_role(organization_id, array['owner','super_admin','hr_admin']));
create policy assignments_select on public.employee_branch_assignments for select to authenticated using (public.is_employee_self(employee_id) or public.is_branch_member(branch_id));
create policy assignments_manage on public.employee_branch_assignments for all to authenticated using (public.can_manage_branch(branch_id)) with check (public.can_manage_branch(branch_id));
create policy ip_rules_select on public.branch_ip_rules for select to authenticated using (public.is_branch_member(branch_id));
create policy ip_rules_manage on public.branch_ip_rules for all to authenticated using (public.can_manage_branch(branch_id)) with check (public.can_manage_branch(branch_id));
create policy schedules_select on public.schedule_templates for select to authenticated using (public.is_org_member(organization_id));
create policy schedules_manage on public.schedule_templates for all to authenticated using (public.has_org_role(organization_id, array['owner','super_admin','hr_admin']) or (branch_id is not null and public.can_manage_branch(branch_id))) with check (public.has_org_role(organization_id, array['owner','super_admin','hr_admin']) or (branch_id is not null and public.can_manage_branch(branch_id)));
create policy employee_schedules_select on public.employee_schedule_assignments for select to authenticated using (public.is_employee_self(employee_id) or exists (select 1 from public.employee_branch_assignments a where a.employee_id = employee_schedule_assignments.employee_id and public.is_branch_member(a.branch_id)));
create policy employee_schedules_manage on public.employee_schedule_assignments for all to authenticated using (exists (select 1 from public.employee_branch_assignments a where a.employee_id = employee_schedule_assignments.employee_id and public.can_manage_branch(a.branch_id))) with check (exists (select 1 from public.employee_branch_assignments a where a.employee_id = employee_schedule_assignments.employee_id and public.can_manage_branch(a.branch_id)));
create policy app_settings_select on public.app_settings for select to authenticated using (public.is_org_member(organization_id));
create policy app_settings_manage on public.app_settings for all to authenticated using (public.has_org_role(organization_id, array['owner','super_admin'])) with check (public.has_org_role(organization_id, array['owner','super_admin']));

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.organizations, public.organization_memberships, public.branches, public.branch_memberships, public.employees, public.employee_branch_assignments, public.branch_ip_rules, public.schedule_templates, public.employee_schedule_assignments, public.app_settings to authenticated;
grant select, insert, update on public.profiles to authenticated;
revoke all on all tables in schema public from anon;
