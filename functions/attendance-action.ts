import { createAdminClient, createClient } from 'npm:@insforge/sdk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization'
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json' }
});

const validDescriptor = (value: unknown): value is number[] => Array.isArray(value)
  && value.length === 512
  && value.every((entry) => typeof entry === 'number' && Number.isFinite(entry) && Math.abs(entry) <= 10);

const bytesFromBase64 = (value: string) => Uint8Array.from(atob(value), (entry) => entry.charCodeAt(0));

const derSignatureToRaw = (signature: Uint8Array): Uint8Array | null => {
  if (signature.length === 64) return signature;
  if (signature.length < 8 || signature[0] !== 0x30) return null;
  let offset = 2;
  if (signature[1] & 0x80) offset = 2 + (signature[1] & 0x7f);
  if (signature[offset] !== 0x02) return null;
  const rLength = signature[offset + 1];
  const r = signature.slice(offset + 2, offset + 2 + rLength);
  offset += 2 + rLength;
  if (signature[offset] !== 0x02) return null;
  const sLength = signature[offset + 1];
  const s = signature.slice(offset + 2, offset + 2 + sLength);
  const raw = new Uint8Array(64);
  raw.set(r.slice(Math.max(0, r.length - 32)), 32 - Math.min(32, r.length));
  raw.set(s.slice(Math.max(0, s.length - 32)), 64 - Math.min(32, s.length));
  return raw;
};

const descriptorDigest = async (descriptor: number[]) => {
  const canonical = descriptor.map((value) => value.toFixed(6)).join(',');
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonical)));
  return Array.from(digest).map((value) => value.toString(16).padStart(2, '0')).join('');
};

export default async function attendanceAction(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const baseUrl = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey = Deno.env.get('API_KEY');
  const anonKey = Deno.env.get('ANON_KEY');
  const authHeader = req.headers.get('Authorization');
  const accessToken = authHeader?.replace(/^Bearer\s+/i, '');
  if (!baseUrl || !apiKey || !anonKey || !accessToken) return json({ error: 'Unauthorized' }, 401);

  const userClient = createClient({ baseUrl, accessToken });
  const { data: userData, error: userError } = await userClient.auth.getCurrentUser();
  const user = userData?.user;
  if (userError || !user?.id) return json({ error: 'Unauthorized' }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: 'Invalid JSON body' }, 400); }
  const forwarded = req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for')?.split(',')[0] || req.headers.get('x-real-ip');
  const sourceIp = forwarded?.trim().replace(/^::ffff:/, '') || null;
  if (sourceIp && !/^[0-9a-fA-F:.]+$/.test(sourceIp)) return json({ error: 'Invalid network address' }, 400);
  const admin = createAdminClient({ baseUrl, apiKey });
  const requestId = String(body.requestId ?? '');
  const branchId = String(body.branchId ?? '');
  if (body.mode === 'diagnose') {
    if (!branchId) return json({ error: 'Branch is required' }, 400);
    const { data: branches, error: branchError } = await userClient.database.from('branches').select('id,name').eq('id', branchId).limit(1);
    if (branchError || !branches?.length) return json({ error: 'Branch access denied' }, 403);
    const { data: rules, error: rulesError } = await admin.database.from('branch_ip_rules').select('label,network,is_active').eq('branch_id', branchId).eq('is_active', true);
    if (rulesError) return json({ error: rulesError.message ?? 'Network diagnostic failed' }, 400);
    return json({ observedIp: sourceIp, activeRules: rules ?? [] });
  }
  if (body.mode === 'offline_sync') {
    const eventType = String(body.eventType ?? '');
    const deviceId = String(body.deviceId ?? '');
    const capturedAt = String(body.capturedAt ?? '');
    const challengeAction = String(body.challengeAction ?? '');
    const signatureValue = String(body.signature ?? '');
    const signedPayload = String(body.signedPayload ?? '');
    const descriptor = body.descriptor;
    const latitude = typeof body.latitude === 'number' ? body.latitude : null;
    const longitude = typeof body.longitude === 'number' ? body.longitude : null;
    const gpsAccuracy = typeof body.gpsAccuracyM === 'number' ? body.gpsAccuracyM : null;
    if (!requestId || !branchId || deviceId.length < 8 || !['check_in','check_out'].includes(eventType)
      || !['blink_turn_left','blink_turn_right','turn_left_blink','turn_right_blink'].includes(challengeAction)
      || !validDescriptor(descriptor) || !signatureValue || !signedPayload || latitude === null || longitude === null || gpsAccuracy === null) {
      return json({ error: 'Invalid offline attendance evidence' }, 400);
    }
    if (body.isSimulated === true || body.isProducedByAccessory === true) return json({ error: 'A trusted iPhone location is required' }, 400);
    const digest = await descriptorDigest(descriptor);
    const expectedPayload = [requestId, branchId, eventType, capturedAt, latitude.toFixed(7), longitude.toFixed(7), gpsAccuracy.toFixed(1), challengeAction, digest].join('|');
    if (signedPayload !== expectedPayload) return json({ error: 'Offline evidence was altered' }, 400);
    const { data: publicKey, error: keyError } = await admin.database.rpc('trusted_device_public_key', { p_actor_user_id: user.id, p_device_id: deviceId });
    if (keyError || typeof publicKey !== 'string') return json({ error: 'This iPhone is not registered as a trusted device' }, 403);
    try {
      const key = await crypto.subtle.importKey('raw', bytesFromBase64(publicKey), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
      const rawSignature = derSignatureToRaw(bytesFromBase64(signatureValue));
      if (!rawSignature || !(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, Uint8Array.from(rawSignature).buffer, new TextEncoder().encode(signedPayload).buffer))) {
        return json({ error: 'Offline evidence signature is invalid' }, 403);
      }
    } catch { return json({ error: 'Offline evidence signature could not be verified' }, 403); }
    const { data: faceResult, error: faceError } = await admin.database.rpc('verify_employee_face', {
      p_actor_user_id: user.id, p_branch_id: branchId, p_device_id: deviceId,
      p_model_version: 'adaface_ir18_v1', p_descriptor: descriptor, p_liveness_passed: true
    });
    if (faceError || faceResult?.matched !== true || !faceResult?.proofId) return json({ error: faceError?.message ?? 'The offline face scan did not match' }, 400);
    const { data: offlineResult, error: offlineError } = await admin.database.rpc('process_offline_attendance', {
      p_actor_user_id: user.id, p_request_id: requestId, p_branch_id: branchId, p_event_type: eventType,
      p_captured_at: capturedAt, p_latitude: latitude, p_longitude: longitude, p_gps_accuracy_m: gpsAccuracy,
      p_device_id: deviceId, p_biometric_proof_id: faceResult.proofId, p_challenge_action: challengeAction, p_signature: signatureValue
    });
    if (offlineError) return json({ error: offlineError.message ?? 'Offline attendance could not be synchronized' }, 400);
    return json(offlineResult);
  }
  const eventType = String(body.eventType ?? '');
  const deviceId = String(body.deviceId ?? '');
  const biometricProofId = body.biometricProofId ? String(body.biometricProofId) : null;
  const overrideEmployeeId = body.overrideEmployeeId ? String(body.overrideEmployeeId) : null;
  const kioskEmployeeId = body.kioskEmployeeId ? String(body.kioskEmployeeId) : null;
  if (!requestId || !branchId || deviceId.length < 8 || !['check_in', 'break_start', 'break_end', 'check_out'].includes(eventType)) return json({ error: 'Invalid attendance request' }, 400);
  if (body.isSimulated === true || body.isProducedByAccessory === true) return json({ error: 'A trusted iPhone location is required' }, 400);

  if (kioskEmployeeId) {
    if (!biometricProofId) return json({ error: 'A fresh kiosk face proof is required' }, 400);
    const { data, error } = await admin.database.rpc('process_kiosk_attendance', {
      p_actor_user_id: user.id,
      p_request_id: requestId,
      p_branch_id: branchId,
      p_employee_id: kioskEmployeeId,
      p_event_type: eventType,
      p_source_ip: sourceIp,
      p_latitude: typeof body.latitude === 'number' ? body.latitude : null,
      p_longitude: typeof body.longitude === 'number' ? body.longitude : null,
      p_gps_accuracy_m: typeof body.gpsAccuracyM === 'number' ? body.gpsAccuracyM : null,
      p_biometric_proof_id: biometricProofId,
      p_device_id: deviceId
    });
    if (error) return json({ error: error.message ?? 'Kiosk attendance processing failed' }, 400);
    return json(data);
  }

  if (overrideEmployeeId) {
    if (!['check_in','check_out'].includes(eventType)) return json({ error: 'Manager overrides support check-in and check-out only' }, 400);
    const password = String(body.managerPassword ?? '');
    const reason = String(body.overrideReason ?? '').trim();
    if (!password || reason.length < 5 || !user.email) return json({ error: 'Password and override reason are required' }, 400);
    const reauthClient = createClient({ baseUrl, anonKey });
    const { data: reauthData, error: reauthError } = await reauthClient.auth.signInWithPassword({ email: user.email, password });
    if (reauthError || reauthData?.user?.id !== user.id) return json({ error: 'Manager password confirmation failed' }, 403);
  }

  const { data, error } = await admin.database.rpc('process_attendance_with_face_proof', {
    p_actor_user_id: user.id,
    p_request_id: requestId,
    p_branch_id: branchId,
    p_event_type: eventType,
    p_source_ip: sourceIp,
    p_latitude: typeof body.latitude === 'number' ? body.latitude : null,
    p_longitude: typeof body.longitude === 'number' ? body.longitude : null,
    p_gps_accuracy_m: typeof body.gpsAccuracyM === 'number' ? body.gpsAccuracyM : null,
    p_biometric_proof_id: biometricProofId,
    p_device_id: deviceId,
    p_override_employee_id: overrideEmployeeId,
    p_override_reason: overrideEmployeeId ? String(body.overrideReason).trim() : null
  });
  if (error) return json({ error: error.message ?? 'Attendance processing failed' }, 400);
  return json(data);
}
