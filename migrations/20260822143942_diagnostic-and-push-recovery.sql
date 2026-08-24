alter table public.app_notifications
  add column if not exists push_retry_requested_at timestamptz;

create index if not exists app_notifications_failed_delivery_idx
  on public.app_notifications(organization_id, created_at desc, id desc)
  where push_sent_at is null and push_attempts > 0 and push_last_error is not null;

create or replace function public.mobile_diagnostic_feed(
  p_branch_id uuid,
  p_severity text default null,
  p_offset integer default 0,
  p_limit integer default 50
) returns table(
  diagnostic_id uuid,
  severity text,
  category text,
  screen text,
  message text,
  error_code text,
  build_version text,
  os_version text,
  model_identifier text,
  device_id text,
  occurred_at timestamptz,
  suggested_action text,
  has_more boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare selected_branch public.branches%rowtype;
begin
  select * into selected_branch from public.branches where id = p_branch_id;
  if selected_branch.id is null or not public.has_org_role(selected_branch.organization_id, array['owner']) then
    raise exception 'owner access required';
  end if;
  if p_severity is not null and p_severity not in ('info','warning','error','crash') then
    raise exception 'invalid severity';
  end if;

  return query
  with filtered as (
    select d.*
    from public.mobile_diagnostic_events d
    where d.organization_id = selected_branch.organization_id
      and (d.branch_id is null or d.branch_id = p_branch_id)
      and (p_severity is null or d.severity = p_severity)
  ), counted as (
    select filtered.*, count(*) over() total_count
    from filtered
  )
  select
    c.id,
    c.severity,
    c.category,
    c.screen,
    c.message,
    c.error_code,
    c.build_version,
    c.os_version,
    c.model_identifier,
    c.device_id,
    c.occurred_at,
    case
      when c.severity = 'crash' then 'Review this screen and build, then compare repeated crashes from the same device model.'
      when c.category like 'authentication%' or c.category like 'session%' then 'Confirm account verification and authentication service health, then ask the user to sign in again.'
      when c.category like 'attendance%' then 'Check the employee assignment, branch IP and GPS settings, then retry the attendance action.'
      when c.category like 'report%' then 'Check backend health and the selected date filters, then retry the report.'
      when c.category like 'push%' or c.category like 'notification%' then 'Open Notification Recovery and retry the failed deliveries.'
      else 'Retry the affected action and review repeated events from the same build and device model.'
    end,
    c.total_count > greatest(p_offset, 0) + least(greatest(p_limit, 1), 100)
  from counted c
  order by c.occurred_at desc, c.id desc
  limit least(greatest(p_limit, 1), 100)
  offset greatest(p_offset, 0);
end
$$;

revoke all on function public.mobile_diagnostic_feed(uuid,text,integer,integer) from public, anon;
grant execute on function public.mobile_diagnostic_feed(uuid,text,integer,integer) to authenticated;

create or replace function public.mobile_failed_push_notifications(
  p_branch_id uuid,
  p_offset integer default 0,
  p_limit integer default 50
) returns table(
  notification_id uuid,
  title text,
  message text,
  category text,
  recipient_name text,
  recipient_code text,
  created_at timestamptz,
  push_attempts integer,
  push_last_error text,
  retry_requested_at timestamptz,
  has_more boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare selected_branch public.branches%rowtype;
begin
  select * into selected_branch from public.branches where id = p_branch_id;
  if selected_branch.id is null or not public.has_org_role(selected_branch.organization_id, array['owner']) then
    raise exception 'owner access required';
  end if;

  return query
  with failed as (
    select
      n.id,
      n.title,
      n.message,
      n.category,
      coalesce(e.full_name, 'Account user') recipient_name,
      e.employee_code recipient_code,
      n.created_at,
      n.push_attempts,
      n.push_last_error,
      n.push_retry_requested_at,
      count(*) over() total_count
    from public.app_notifications n
    left join public.employees e
      on e.organization_id = n.organization_id and e.user_id = n.user_id
    where n.organization_id = selected_branch.organization_id
      and n.push_sent_at is null
      and n.push_attempts > 0
      and n.push_last_error is not null
  )
  select
    f.id,
    f.title,
    f.message,
    f.category,
    f.recipient_name,
    f.recipient_code,
    f.created_at,
    f.push_attempts,
    f.push_last_error,
    f.push_retry_requested_at,
    f.total_count > greatest(p_offset, 0) + least(greatest(p_limit, 1), 100)
  from failed f
  order by f.created_at desc, f.id desc
  limit least(greatest(p_limit, 1), 100)
  offset greatest(p_offset, 0);
end
$$;

revoke all on function public.mobile_failed_push_notifications(uuid,integer,integer) from public, anon;
grant execute on function public.mobile_failed_push_notifications(uuid,integer,integer) to authenticated;

create or replace function public.retry_failed_push_notification(
  p_branch_id uuid,
  p_notification_id uuid
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare selected_branch public.branches%rowtype;
declare changed boolean := false;
begin
  select * into selected_branch from public.branches where id = p_branch_id;
  if selected_branch.id is null or not public.has_org_role(selected_branch.organization_id, array['owner']) then
    raise exception 'owner access required';
  end if;

  update public.app_notifications n
  set push_attempts = 0,
      push_last_error = null,
      push_sent_at = null,
      push_retry_requested_at = now()
  where n.id = p_notification_id
    and n.organization_id = selected_branch.organization_id
    and n.push_sent_at is null
    and n.push_attempts > 0
  returning true into changed;

  if coalesce(changed, false) then
    insert into public.audit_events(
      organization_id, branch_id, actor_user_id, action, entity_type, entity_id, metadata
    ) values (
      selected_branch.organization_id, selected_branch.id, auth.uid(),
      'notification.retry_requested', 'app_notification', p_notification_id,
      jsonb_build_object('scope', 'single')
    );
  end if;
  return coalesce(changed, false);
end
$$;

revoke all on function public.retry_failed_push_notification(uuid,uuid) from public, anon;
grant execute on function public.retry_failed_push_notification(uuid,uuid) to authenticated;

create or replace function public.retry_all_failed_push_notifications(
  p_branch_id uuid
) returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare selected_branch public.branches%rowtype;
declare changed integer := 0;
begin
  select * into selected_branch from public.branches where id = p_branch_id;
  if selected_branch.id is null or not public.has_org_role(selected_branch.organization_id, array['owner']) then
    raise exception 'owner access required';
  end if;

  update public.app_notifications n
  set push_attempts = 0,
      push_last_error = null,
      push_sent_at = null,
      push_retry_requested_at = now()
  where n.organization_id = selected_branch.organization_id
    and n.push_sent_at is null
    and n.push_attempts > 0
    and n.push_last_error is not null;
  get diagnostics changed = row_count;

  if changed > 0 then
    insert into public.audit_events(
      organization_id, branch_id, actor_user_id, action, entity_type, metadata
    ) values (
      selected_branch.organization_id, selected_branch.id, auth.uid(),
      'notification.retry_all_requested', 'app_notification',
      jsonb_build_object('count', changed)
    );
  end if;
  return changed;
end
$$;

revoke all on function public.retry_all_failed_push_notifications(uuid) from public, anon;
grant execute on function public.retry_all_failed_push_notifications(uuid) to authenticated;

create or replace function public.claim_push_notification_batch(p_limit integer default 50)
returns table(notification_id uuid,user_id uuid,title text,message text,category text,token text,environment text)
language sql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  with candidates as (
    select n.id
    from public.app_notifications n
    left join public.notification_preferences p on p.user_id = n.user_id
    where n.push_sent_at is null
      and n.push_attempts < 10
      and greatest(n.created_at, coalesce(n.push_retry_requested_at, n.created_at)) > now() - interval '3 days'
      and coalesce(p.push_enabled, true)
      and case
        when n.category like 'attendance%' then coalesce(p.attendance_enabled, true)
        when n.category in ('shift','schedule','shift_swap') then coalesce(p.shifts_enabled, true)
        when n.category like 'leave%' then coalesce(p.leave_enabled, true)
        when n.category like 'payroll%' then coalesce(p.payroll_enabled, true)
        when n.category = 'documents' then coalesce(p.documents_enabled, true)
        else true
      end
      and (
        p.quiet_start is null or p.quiet_end is null
        or not case
          when p.quiet_start <= p.quiet_end then localtime >= p.quiet_start and localtime < p.quiet_end
          else localtime >= p.quiet_start or localtime < p.quiet_end
        end
      )
    order by coalesce(n.push_retry_requested_at, n.created_at), n.created_at, n.id
    limit least(greatest(p_limit, 1), 100)
    for update of n skip locked
  ), claimed as (
    update public.app_notifications n
    set push_attempts = n.push_attempts + 1
    from candidates c
    where n.id = c.id
    returning n.*
  )
  select c.id, c.user_id, c.title, c.message, c.category, t.token, t.environment
  from claimed c
  join public.mobile_push_tokens t on t.user_id = c.user_id and t.is_active;
$$;

create or replace function public.complete_push_notification(
  p_notification_id uuid,
  p_sent boolean,
  p_error text default null
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  update public.app_notifications
  set push_sent_at = case when p_sent then now() else push_sent_at end,
      push_last_error = case when p_sent then null else left(p_error, 500) end,
      push_retry_requested_at = case when p_sent then null else push_retry_requested_at end
  where id = p_notification_id;
  return found;
end
$$;

revoke all on function public.claim_push_notification_batch(integer) from public, anon, authenticated;
revoke all on function public.complete_push_notification(uuid,boolean,text) from public, anon, authenticated;
