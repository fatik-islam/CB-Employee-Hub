-- The product supports employee-owned and restaurant-owned iOS/Android devices
-- without platform attestation. Keep the ordinary trusted-device key used to
-- identify devices and verify signed offline attendance evidence.
drop function if exists public.set_device_integrity_result(uuid,text,text,text);

drop index if exists public.trusted_devices_integrity_idx;

alter table public.trusted_devices
  drop column if exists integrity_provider,
  drop column if exists integrity_state,
  drop column if exists integrity_checked_at;
