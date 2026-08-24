create or replace function public.consume_biometric_challenge(
  p_challenge_id uuid,
  p_actor_user_id uuid,
  p_branch_id uuid,
  p_device_id text,
  p_action text
)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare consumed uuid;
begin
  update public.biometric_scan_challenges set consumed_at=now()
    where id=p_challenge_id and user_id=p_actor_user_id and branch_id=p_branch_id
      and device_id=p_device_id and action=p_action and consumed_at is null and expires_at>now()
    returning id into consumed;
  return consumed is not null;
end $$;

revoke all on function public.consume_biometric_challenge(uuid,uuid,uuid,text,text) from public,anon,authenticated;
