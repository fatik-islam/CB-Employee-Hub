-- Close the default PostgreSQL function-execution surface without changing the
-- authenticated RPCs that the mobile application intentionally uses.
-- Security-definer functions in this project are owned by project_admin and
-- pin their search path; anonymous callers must never inherit PUBLIC execute.
do $$
declare
  function_signature text;
begin
  for function_signature in
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    execute format('revoke all on function public.%s from public, anon', function_signature);
  end loop;
end
$$;

-- New functions must also start closed. Explicit grants are added alongside
-- each application RPC after its authorization checks are defined.
alter default privileges for role project_admin in schema public
  revoke execute on functions from public;

-- This schedule helper is used only inside the attendance recalculation
-- pipeline. It was never called by the iOS client and must not be a direct RPC.
revoke all on function public.employee_schedule_for_date(uuid,date)
  from public, anon, authenticated;
grant execute on function public.employee_schedule_for_date(uuid,date)
  to project_admin;

-- Trigger functions and recalculation internals are executable only by their
-- owning database role. Attendance writes continue through the authorized
-- record_attendance_event RPC.
revoke all on function public.recalculate_attendance_after_event()
  from public, anon, authenticated;
revoke all on function public.recalculate_attendance_day(uuid,uuid,date)
  from public, anon, authenticated;

-- The one-time owner bootstrap remains callable by signed-in users because the
-- app uses it before a membership exists. Its body independently enforces the
-- approved email hash, an unclaimed organization, and no existing membership.
revoke all on function public.bootstrap_organization(text,text,text)
  from public, anon;
grant execute on function public.bootstrap_organization(text,text,text)
  to authenticated;

-- Retain the passive liveness measurements used for each short-lived proof so
-- suspicious attempts can be audited without retaining any image or video.
alter table public.face_verification_proofs
  add column if not exists capture_version text not null default 'legacy',
  add column if not exists liveness_evidence jsonb not null default '{}'::jsonb;

alter table public.face_verification_proofs
  drop constraint if exists face_verification_proofs_liveness_evidence_object;
alter table public.face_verification_proofs
  add constraint face_verification_proofs_liveness_evidence_object
  check (jsonb_typeof(liveness_evidence) = 'object');

comment on column public.face_verification_proofs.liveness_evidence is
  'Non-image temporal liveness measurements. Raw photos and video are never retained.';
