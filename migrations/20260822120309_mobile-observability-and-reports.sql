create table public.mobile_diagnostic_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  severity text not null check (severity in ('info','warning','error','crash')),
  category text not null,
  screen text,
  message text not null,
  error_code text,
  build_version text not null,
  os_version text not null,
  model_identifier text not null,
  payload_text text,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (length(device_id) between 8 and 100),
  check (length(category) between 2 and 80),
  check (length(message) between 1 and 1000),
  check (payload_text is null or octet_length(payload_text) <= 262144)
);

alter table public.mobile_diagnostic_events enable row level security;

create policy mobile_diagnostics_insert_own
on public.mobile_diagnostic_events for insert to authenticated
with check (
  user_id = (select auth.uid())
  and public.is_org_member(organization_id)
  and (
    branch_id is null
    or exists (
      select 1 from public.branches b
      where b.id = branch_id and b.organization_id = mobile_diagnostic_events.organization_id
    )
  )
);

create policy mobile_diagnostics_owner_read
on public.mobile_diagnostic_events for select to authenticated
using (public.has_org_role(organization_id, array['owner']));

grant select, insert on public.mobile_diagnostic_events to authenticated;
revoke update, delete on public.mobile_diagnostic_events from anon, authenticated;
create index mobile_diagnostics_org_created_idx on public.mobile_diagnostic_events(organization_id, created_at desc);
create index mobile_diagnostics_branch_created_idx on public.mobile_diagnostic_events(branch_id, created_at desc) where branch_id is not null;
create index mobile_diagnostics_crash_idx on public.mobile_diagnostic_events(organization_id, severity, occurred_at desc);

create or replace function public.record_mobile_diagnostic(
  p_organization_id uuid,
  p_branch_id uuid,
  p_device_id text,
  p_severity text,
  p_category text,
  p_screen text,
  p_message text,
  p_error_code text,
  p_build_version text,
  p_os_version text,
  p_model_identifier text,
  p_payload_text text,
  p_occurred_at timestamptz
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare result uuid;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then
    raise exception 'organization membership required';
  end if;
  if p_branch_id is not null and not exists (
    select 1 from public.branches b where b.id=p_branch_id and b.organization_id=p_organization_id
  ) then raise exception 'invalid branch'; end if;
  if p_severity not in ('info','warning','error','crash') then raise exception 'invalid severity'; end if;
  if length(trim(coalesce(p_device_id,'')))<8 or length(trim(coalesce(p_category,'')))<2 or length(trim(coalesce(p_message,'')))<1 then
    raise exception 'invalid diagnostic';
  end if;

  insert into public.mobile_diagnostic_events(
    organization_id,branch_id,user_id,device_id,severity,category,screen,message,error_code,
    build_version,os_version,model_identifier,payload_text,occurred_at
  ) values (
    p_organization_id,p_branch_id,auth.uid(),left(trim(p_device_id),100),p_severity,left(trim(p_category),80),
    left(nullif(trim(p_screen),''),120),left(trim(p_message),1000),left(nullif(trim(p_error_code),''),120),
    left(coalesce(nullif(trim(p_build_version),''),'unknown'),40),left(coalesce(nullif(trim(p_os_version),''),'unknown'),80),
    left(coalesce(nullif(trim(p_model_identifier),''),'unknown'),80),left(p_payload_text,262144),coalesce(p_occurred_at,now())
  ) returning id into result;
  return result;
end $$;

revoke all on function public.record_mobile_diagnostic(uuid,uuid,text,text,text,text,text,text,text,text,text,text,timestamptz) from public, anon;
grant execute on function public.record_mobile_diagnostic(uuid,uuid,text,text,text,text,text,text,text,text,text,text,timestamptz) to authenticated;

create or replace function public.mobile_attendance_history(
  p_employee_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date,
  p_limit integer default 50,
  p_offset integer default 0
) returns table(
  record_id uuid,
  employee_id uuid,
  employee_name text,
  employee_code text,
  branch_id uuid,
  branch_name text,
  work_date date,
  status text,
  first_check_in_at timestamptz,
  last_check_out_at timestamptz,
  worked_minutes integer,
  scheduled_minutes integer,
  break_minutes integer,
  late_minutes integer,
  overtime_minutes integer,
  shortfall_minutes integer,
  mark_method text,
  used_override boolean,
  correction_status text,
  has_more boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  with history as (
    select
      d.id record_id,d.employee_id,e.full_name employee_name,e.employee_code,d.branch_id,b.name branch_name,
      d.work_date,d.status,d.first_check_in_at,d.last_check_out_at,d.worked_minutes,d.scheduled_minutes,
      d.break_minutes,d.late_minutes,d.overtime_minutes,d.shortfall_minutes,
      case
        when coalesce(attempt.used_override,false) then 'override'
        when event.source='offline_verified' then 'offline'
        when coalesce(attempt.ip_passed,false) then 'ip'
        when coalesce(attempt.gps_passed,false) then 'gps'
        else coalesce(event.source,'recorded')
      end mark_method,
      coalesce(attempt.used_override,false) used_override,
      correction.status correction_status
    from public.attendance_daily d
    join public.employees e on e.id=d.employee_id
    join public.branches b on b.id=d.branch_id
    left join lateral (
      select a.ip_passed,a.gps_passed,a.used_override
      from public.attendance_attempts a
      where a.employee_id=d.employee_id and a.branch_id=d.branch_id and a.outcome='accepted'
        and (a.created_at at time zone b.timezone)::date=d.work_date
      order by a.created_at desc,a.id desc limit 1
    ) attempt on true
    left join lateral (
      select ae.source
      from public.attendance_events ae
      where ae.employee_id=d.employee_id and ae.branch_id=d.branch_id and ae.local_work_date=d.work_date
      order by ae.occurred_at desc,ae.id desc limit 1
    ) event on true
    left join lateral (
      select c.status
      from public.attendance_correction_requests c
      where c.employee_id=d.employee_id and c.branch_id=d.branch_id and c.work_date=d.work_date
      order by c.created_at desc,c.id desc limit 1
    ) correction on true
    where d.work_date between least(p_from,p_to) and greatest(p_from,p_to)
      and (p_employee_id is null or d.employee_id=p_employee_id)
      and (p_branch_id is null or d.branch_id=p_branch_id)
      and (public.is_employee_self(d.employee_id) or public.can_manage_branch(d.branch_id))
  ), counted as (
    select history.*,count(*) over() total_count from history
  )
  select record_id,employee_id,employee_name,employee_code,branch_id,branch_name,work_date,status,
    first_check_in_at,last_check_out_at,worked_minutes,scheduled_minutes,break_minutes,late_minutes,
    overtime_minutes,shortfall_minutes,mark_method,used_override,correction_status,
    total_count > greatest(p_offset,0)+least(greatest(p_limit,1),100) has_more
  from counted
  order by work_date desc,employee_name,record_id
  limit least(greatest(p_limit,1),100) offset greatest(p_offset,0);
$$;

revoke all on function public.mobile_attendance_history(uuid,uuid,date,date,integer,integer) from public, anon;
grant execute on function public.mobile_attendance_history(uuid,uuid,date,date,integer,integer) to authenticated;

create or replace function public.mobile_workforce_report_v2(
  p_branch_id uuid,
  p_from date,
  p_to date,
  p_kind text default 'all',
  p_employee_id uuid default null,
  p_status text default null,
  p_mark_method text default null,
  p_used_override boolean default null,
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0
) returns table(
  report_type text,
  record_id uuid,
  employee_id uuid,
  employee_name text,
  employee_code text,
  record_date date,
  status text,
  amount_minor bigint,
  details text,
  branch_name text,
  mark_method text,
  used_override boolean,
  late_minutes integer,
  overtime_minutes integer,
  rejection_code text,
  has_more boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  with raw_rows as (
    select 'attendance'::text report_type,d.id record_id,d.employee_id,e.full_name employee_name,e.employee_code,
      d.work_date record_date,d.status,null::bigint amount_minor,
      concat_ws(' · ',case when d.first_check_in_at is not null then 'In '||to_char(d.first_check_in_at at time zone b.timezone,'HH24:MI') end,
        case when d.last_check_out_at is not null then 'Out '||to_char(d.last_check_out_at at time zone b.timezone,'HH24:MI') end,
        'Worked '||d.worked_minutes||' min') details,b.name branch_name,
      case when coalesce(a.used_override,false) then 'override' when coalesce(a.ip_passed,false) then 'ip'
        when coalesce(a.gps_passed,false) then 'gps' else coalesce(ev.source,'recorded') end mark_method,
      coalesce(a.used_override,false) used_override,d.late_minutes,d.overtime_minutes,null::text rejection_code
    from public.attendance_daily d
    join public.employees e on e.id=d.employee_id
    join public.branches b on b.id=d.branch_id
    left join lateral (
      select aa.ip_passed,aa.gps_passed,aa.used_override from public.attendance_attempts aa
      where aa.employee_id=d.employee_id and aa.branch_id=d.branch_id and aa.outcome='accepted'
        and (aa.created_at at time zone b.timezone)::date=d.work_date
      order by aa.created_at desc,aa.id desc limit 1
    ) a on true
    left join lateral (
      select ae.source from public.attendance_events ae where ae.employee_id=d.employee_id and ae.branch_id=d.branch_id
        and ae.local_work_date=d.work_date order by ae.occurred_at desc,ae.id desc limit 1
    ) ev on true
    where p_kind in ('all','attendance') and d.branch_id=p_branch_id and d.work_date between least(p_from,p_to) and greatest(p_from,p_to)
      and (public.can_manage_branch(p_branch_id) or public.is_employee_self(d.employee_id))

    union all

    select 'attendance'::text,aa.id,aa.employee_id,e.full_name,e.employee_code,
      (aa.created_at at time zone b.timezone)::date,'rejected',null::bigint,
      'Rejected · '||coalesce(aa.rejection_code,'unknown'),b.name,
      case when aa.used_override then 'override' when aa.ip_passed then 'ip' when aa.gps_passed then 'gps' else 'unverified' end,
      aa.used_override,0,0,aa.rejection_code
    from public.attendance_attempts aa
    join public.employees e on e.id=aa.employee_id
    join public.branches b on b.id=aa.branch_id
    where p_kind in ('all','attendance') and aa.branch_id=p_branch_id and aa.outcome='rejected'
      and (aa.created_at at time zone b.timezone)::date between least(p_from,p_to) and greatest(p_from,p_to)
      and (public.can_manage_branch(p_branch_id) or public.is_employee_self(aa.employee_id))

    union all

    select 'leave',l.id,l.employee_id,e.full_name,e.employee_code,l.start_date,l.status,null::bigint,
      coalesce(l.requested_days,0)||' day(s) · '||l.start_date||' to '||l.end_date,b.name,null::text,false,0,0,null::text
    from public.leave_requests l join public.employees e on e.id=l.employee_id join public.branches b on b.id=l.branch_id
    where p_kind in ('all','leave') and l.branch_id=p_branch_id and l.start_date<=greatest(p_from,p_to) and l.end_date>=least(p_from,p_to)
      and (public.can_manage_branch(p_branch_id) or public.is_employee_self(l.employee_id))

    union all

    select 'payroll',pi.id,pi.employee_id,e.full_name,e.employee_code,r.period_end,pi.status,pi.net_minor,r.title,b.name,
      null::text,false,0,0,null::text
    from public.payroll_items pi join public.payroll_runs r on r.id=pi.payroll_run_id join public.employees e on e.id=pi.employee_id
      left join public.branches b on b.id=coalesce(r.branch_id,p_branch_id)
    where p_kind in ('all','payroll') and (r.branch_id=p_branch_id or (r.branch_id is null and e.organization_id=r.organization_id))
      and r.period_start<=greatest(p_from,p_to) and r.period_end>=least(p_from,p_to)
      and (public.is_employee_self(pi.employee_id) or public.can_manage_payroll(r.organization_id))
  ), filtered as (
    select raw_rows.*
    from raw_rows
    where (p_employee_id is null or employee_id=p_employee_id)
      and (nullif(trim(p_status),'') is null or status=p_status)
      and (nullif(trim(p_mark_method),'') is null or mark_method=p_mark_method)
      and (p_used_override is null or used_override=p_used_override)
      and (
        nullif(trim(p_search),'') is null
        or employee_name ilike '%'||trim(p_search)||'%'
        or employee_code ilike '%'||trim(p_search)||'%'
        or coalesce(details,'') ilike '%'||trim(p_search)||'%'
        or coalesce(rejection_code,'') ilike '%'||trim(p_search)||'%'
      )
  ), counted as (
    select filtered.*,count(*) over() total_count from filtered
  )
  select report_type,record_id,employee_id,employee_name,employee_code,record_date,status,amount_minor,details,
    branch_name,mark_method,used_override,late_minutes,overtime_minutes,rejection_code,
    total_count > greatest(p_offset,0)+least(greatest(p_limit,1),500) has_more
  from counted
  order by record_date desc,employee_name,record_id
  limit least(greatest(p_limit,1),500) offset greatest(p_offset,0);
$$;

revoke all on function public.mobile_workforce_report_v2(uuid,date,date,text,uuid,text,text,boolean,text,integer,integer) from public, anon;
grant execute on function public.mobile_workforce_report_v2(uuid,date,date,text,uuid,text,text,boolean,text,integer,integer) to authenticated;

create or replace function public.mobile_operations_health(p_branch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare b public.branches%rowtype;result jsonb;
begin
  select * into b from public.branches where id=p_branch_id;
  if b.id is null or not public.has_org_role(b.organization_id,array['owner']) then raise exception 'owner access required'; end if;

  select jsonb_build_object(
    'backendOk',true,
    'generatedAt',now(),
    'activeEmployees',(select count(distinct e.id) from public.employees e join public.employee_branch_assignments a on a.employee_id=e.id
      where a.branch_id=b.id and e.employment_status='active' and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date)),
    'missingBranchLocation',b.latitude is null or b.longitude is null,
    'activeIPRules',(select count(*) from public.branch_ip_rules r where r.branch_id=b.id and r.is_active),
    'missingFaceEnrollments',(select count(distinct e.id) from public.employees e join public.employee_branch_assignments a on a.employee_id=e.id
      where a.branch_id=b.id and e.employment_status='active' and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date)
        and not exists(select 1 from public.employee_face_templates f where f.employee_id=e.id and f.revoked_at is null)),
    'missingSchedules',(select count(distinct e.id) from public.employees e join public.employee_branch_assignments a on a.employee_id=e.id
      where a.branch_id=b.id and e.employment_status='active' and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date)
        and not exists(select 1 from public.employee_schedule_assignments s where s.employee_id=e.id and s.effective_from<=current_date and (s.effective_to is null or s.effective_to>=current_date))),
    'missingCompensations',(select count(distinct e.id) from public.employees e join public.employee_branch_assignments a on a.employee_id=e.id
      where a.branch_id=b.id and e.employment_status='active' and a.starts_on<=current_date and (a.ends_on is null or a.ends_on>=current_date)
        and not exists(select 1 from public.compensation_versions c where c.employee_id=e.id and c.effective_from<=current_date and (c.effective_to is null or c.effective_to>=current_date))),
    'pendingPushNotifications',(select count(*) from public.app_notifications n where n.organization_id=b.organization_id and n.push_sent_at is null),
    'failedPushNotifications',(select count(*) from public.app_notifications n where n.organization_id=b.organization_id and n.push_sent_at is null and n.push_attempts>0 and n.push_last_error is not null),
    'attendanceRejections7d',(select count(*) from public.attendance_attempts a where a.branch_id=b.id and a.outcome='rejected' and a.created_at>=now()-interval '7 days'),
    'crashes7d',(select count(*) from public.mobile_diagnostic_events d where d.organization_id=b.organization_id and d.severity='crash' and d.occurred_at>=now()-interval '7 days'),
    'errors7d',(select count(*) from public.mobile_diagnostic_events d where d.organization_id=b.organization_id and d.severity in ('error','crash') and d.occurred_at>=now()-interval '7 days'),
    'lastCrashAt',(select max(d.occurred_at) from public.mobile_diagnostic_events d where d.organization_id=b.organization_id and d.severity='crash'),
    'lastPushSentAt',(select max(n.push_sent_at) from public.app_notifications n where n.organization_id=b.organization_id),
    'lastAttendanceAt',(select max(a.created_at) from public.attendance_attempts a where a.branch_id=b.id and a.outcome='accepted'),
    'topRejectionReasons',coalesce((
      select jsonb_agg(jsonb_build_object('code',x.rejection_code,'count',x.total) order by x.total desc,x.rejection_code)
      from (
        select coalesce(a.rejection_code,'unknown') rejection_code,count(*) total from public.attendance_attempts a
        where a.branch_id=b.id and a.outcome='rejected' and a.created_at>=now()-interval '7 days'
        group by coalesce(a.rejection_code,'unknown') order by count(*) desc limit 5
      ) x
    ),'[]'::jsonb)
  ) into result;
  return result;
end $$;

revoke all on function public.mobile_operations_health(uuid) from public, anon;
grant execute on function public.mobile_operations_health(uuid) to authenticated;
