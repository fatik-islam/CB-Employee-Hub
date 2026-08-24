drop policy if exists app_notifications_select on public.app_notifications;
drop policy if exists app_notifications_update on public.app_notifications;
create policy app_notifications_select on public.app_notifications for select to authenticated
  using (user_id=(select auth.uid()));
create policy app_notifications_update on public.app_notifications for update to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));

create index if not exists app_notifications_organization_idx
  on public.app_notifications(organization_id);
