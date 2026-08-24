-- Remove PostgreSQL's implicit PUBLIC execution path from privileged RPCs.
-- App-facing RPCs retain their explicit authenticated grants from prior migrations;
-- internal automation RPCs remain service-role only.
do $$
declare privileged_function record;
begin
  for privileged_function in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
  loop
    execute format('revoke all on function %s from public, anon',privileged_function.signature);
    execute format('alter function %s set search_path to pg_catalog, public, pg_temp',privileged_function.signature);
  end loop;
end $$;

create index if not exists employee_availability_branch_idx
  on public.employee_availability(branch_id);
create index if not exists offline_attendance_org_idx
  on public.offline_attendance_submissions(organization_id);
