-- Supports owner-only diagnostic RLS lookups and the auth.users foreign key.
create index if not exists mobile_diagnostic_events_user_idx
  on public.mobile_diagnostic_events(user_id);
