create policy employee_face_templates_deny_client_access
  on public.employee_face_templates
  for all
  to authenticated
  using (false)
  with check (false);

create policy face_verification_proofs_deny_client_access
  on public.face_verification_proofs
  for all
  to authenticated
  using (false)
  with check (false);

create index employee_face_templates_enrolled_by_idx
  on public.employee_face_templates(enrolled_by);
create index employee_face_templates_revoked_by_idx
  on public.employee_face_templates(revoked_by)
  where revoked_by is not null;
create index face_verification_proofs_organization_idx
  on public.face_verification_proofs(organization_id);
create index face_verification_proofs_branch_idx
  on public.face_verification_proofs(branch_id);
create index face_verification_proofs_employee_idx
  on public.face_verification_proofs(employee_id);
create index face_verification_proofs_template_idx
  on public.face_verification_proofs(template_id);
create index attendance_attempts_biometric_proof_idx
  on public.attendance_attempts(biometric_proof_id)
  where biometric_proof_id is not null;
