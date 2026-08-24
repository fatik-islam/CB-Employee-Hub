alter table public.app_notifications
  add column push_sent_at timestamptz,
  add column push_attempts integer not null default 0 check(push_attempts between 0 and 20),
  add column push_last_error text;

create index app_notifications_push_queue_idx on public.app_notifications(created_at)
  where push_sent_at is null and push_attempts<10;

create or replace function public.claim_push_notification_batch(p_limit integer default 50)
returns table(notification_id uuid,user_id uuid,title text,message text,category text,token text,environment text)
language sql security definer set search_path=pg_catalog,public,pg_temp as $$
  with candidates as (
    select n.id from public.app_notifications n
    where n.push_sent_at is null and n.push_attempts<10 and n.created_at>now()-interval '3 days'
    order by n.created_at limit least(greatest(p_limit,1),100)
    for update skip locked
  ), claimed as (
    update public.app_notifications n set push_attempts=push_attempts+1
    from candidates c where n.id=c.id
    returning n.*
  )
  select c.id,c.user_id,c.title,c.message,c.category,t.token,t.environment
  from claimed c join public.mobile_push_tokens t on t.user_id=c.user_id and t.is_active;
$$;

create or replace function public.complete_push_notification(p_notification_id uuid,p_sent boolean,p_error text default null)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  update public.app_notifications set push_sent_at=case when p_sent then now() else push_sent_at end,push_last_error=case when p_sent then null else left(p_error,500) end where id=p_notification_id;
  return found;
end $$;

create or replace function public.deactivate_mobile_push_token(p_token text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin update public.mobile_push_tokens set is_active=false where token=p_token;return found;end $$;

revoke all on function public.claim_push_notification_batch(integer),public.complete_push_notification(uuid,boolean,text),public.deactivate_mobile_push_token(text) from public,anon,authenticated;
