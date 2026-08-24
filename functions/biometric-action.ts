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

type PreparedCapture = {
  descriptor: number[];
  sampleCount: number;
  consistency: number;
  isMultiFrame: boolean;
};

type LivenessEvidence = {
  captureDurationMs: number;
  qualifiedFrames: number;
  naturalMotionScore: number;
  maxFrameJump: number;
  blinkAmplitude: number;
  turnAmplitude: number;
  challengeOrderPassed: boolean;
  passivePassed: boolean;
};

const validLivenessEvidence = (value: unknown): value is LivenessEvidence => {
  if (!value || typeof value !== 'object') return false;
  const evidence = value as Record<string, unknown>;
  const numeric = ['captureDurationMs', 'qualifiedFrames', 'naturalMotionScore', 'maxFrameJump', 'blinkAmplitude', 'turnAmplitude']
    .every((key) => typeof evidence[key] === 'number' && Number.isFinite(evidence[key]));
  if (!numeric || evidence.challengeOrderPassed !== true || evidence.passivePassed !== true) return false;
  return Number.isInteger(evidence.captureDurationMs) && Number.isInteger(evidence.qualifiedFrames)
    && (evidence.captureDurationMs as number) >= 650 && (evidence.captureDurationMs as number) <= 15000
    && (evidence.qualifiedFrames as number) >= 8 && (evidence.qualifiedFrames as number) <= 360
    && (evidence.naturalMotionScore as number) >= 0.58 && (evidence.naturalMotionScore as number) <= 1
    && (evidence.maxFrameJump as number) >= 0 && (evidence.maxFrameJump as number) <= 0.16
    && (evidence.blinkAmplitude as number) >= 0.035 && (evidence.blinkAmplitude as number) <= 1
    && (evidence.turnAmplitude as number) >= 0.10 && (evidence.turnAmplitude as number) <= 2;
};

const canonicalLivenessEvidence = (evidence: LivenessEvidence) => [
  evidence.captureDurationMs.toString(), evidence.qualifiedFrames.toString(),
  evidence.naturalMotionScore.toFixed(4), evidence.maxFrameJump.toFixed(4),
  evidence.blinkAmplitude.toFixed(4), evidence.turnAmplitude.toFixed(4), '1', '1'
].join(',');

const normalize = (descriptor: number[]): number[] | null => {
  const magnitude = Math.sqrt(descriptor.reduce((sum, value) => sum + value * value, 0));
  if (!Number.isFinite(magnitude) || magnitude < 0.5 || magnitude > 1.5) return null;
  return descriptor.map((value) => value / magnitude);
};

const cosine = (left: number[], right: number[]) => left.reduce((sum, value, index) => sum + value * right[index], 0);

const average = (samples: number[][]): number[] | null => {
  const combined = new Array<number>(512).fill(0);
  for (const sample of samples) sample.forEach((value, index) => { combined[index] += value; });
  return normalize(combined.map((value) => value / samples.length));
};

const prepareCapture = (body: Record<string, unknown>, mode: 'enroll' | 'verify'): PreparedCapture | null => {
  const supplied = Array.isArray(body.descriptors) ? body.descriptors : null;
  const isMultiFrame = supplied !== null;
  const raw = supplied ?? [body.descriptor];
  const maximum = mode === 'enroll' ? 8 : 5;
  if (raw.length < 1 || raw.length > maximum || !raw.every(validDescriptor)) return null;

  const normalized = (raw as number[][]).map(normalize);
  if (normalized.some((value) => value === null)) return null;
  const samples = normalized as number[][];
  const medoid = samples.reduce((best, candidate) => {
    const candidateScore = samples.reduce((sum, sample) => sum + cosine(candidate, sample), 0);
    const bestScore = samples.reduce((sum, sample) => sum + cosine(best, sample), 0);
    return candidateScore > bestScore ? candidate : best;
  }, samples[0]);
  const accepted = samples.filter((sample) => cosine(sample, medoid) >= 0.42);
  const minimum = mode === 'enroll' ? 4 : 3;
  if (isMultiFrame && accepted.length < minimum) return null;

  const pairScores: number[] = [];
  for (let left = 0; left < accepted.length; left += 1) {
    for (let right = left + 1; right < accepted.length; right += 1) pairScores.push(cosine(accepted[left], accepted[right]));
  }
  const consistency = pairScores.length === 0 ? 1 : pairScores.reduce((sum, score) => sum + score, 0) / pairScores.length;
  if (isMultiFrame && consistency < 0.45) return null;
  const descriptor = average(accepted);
  return descriptor ? { descriptor, sampleCount: accepted.length, consistency, isMultiFrame } : null;
};

export default async function biometricAction(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const baseUrl = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey = Deno.env.get('API_KEY');
  const authHeader = req.headers.get('Authorization');
  const accessToken = authHeader?.replace(/^Bearer\s+/i, '');
  if (!baseUrl || !apiKey || !accessToken) return json({ error: 'Unauthorized' }, 401);

  const userClient = createClient({ baseUrl, accessToken });
  const { data: userData, error: userError } = await userClient.auth.getCurrentUser();
  const user = userData?.user;
  if (userError || !user?.id) return json({ error: 'Unauthorized' }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: 'Invalid JSON body' }, 400); }
  const mode = String(body.mode ?? '');
  const admin = createAdminClient({ baseUrl, apiKey });

  let rpcName: string;
  let args: Record<string, unknown>;
  if (mode === 'status') {
    const employeeId = String(body.employeeId ?? '');
    if (!employeeId) return json({ error: 'Employee is required' }, 400);
    rpcName = 'face_template_status';
    args = { p_actor_user_id: user.id, p_employee_id: employeeId };
  } else if (mode === 'enroll') {
    const employeeId = String(body.employeeId ?? '');
    const capture = prepareCapture(body, 'enroll');
    const liveness = body.livenessEvidence;
    if (!employeeId || !capture || body.captureVersion !== 'challenge_temporal_v5' || !validLivenessEvidence(liveness)) {
      return json({ error: 'Live face evidence was incomplete. Blink and turn naturally, then try again.' }, 400);
    }
    rpcName = 'enroll_employee_face';
    args = {
      p_actor_user_id: user.id,
      p_employee_id: employeeId,
      p_model_version: String(body.modelVersion ?? ''),
      p_descriptor: capture.descriptor,
      p_sample_count: capture.isMultiFrame ? capture.sampleCount : Number(body.sampleCount ?? 0)
    };
  } else if (mode === 'revoke') {
    const employeeId = String(body.employeeId ?? '');
    const reason = String(body.reason ?? '').trim();
    if (!employeeId || reason.length < 5) return json({ error: 'Employee and revocation reason are required' }, 400);
    rpcName = 'revoke_employee_face';
    args = { p_actor_user_id: user.id, p_employee_id: employeeId, p_reason: reason };
  } else if (mode === 'verify' || mode === 'verify_kiosk') {
    const branchId = String(body.branchId ?? '');
    const employeeId = mode === 'verify_kiosk' ? String(body.employeeId ?? '') : '';
    const deviceId = String(body.deviceId ?? '');
    const challengeId = String(body.challengeId ?? '');
    const challengeAction = String(body.challengeAction ?? '');
    const signedPayload = String(body.signedPayload ?? '');
    const signatureValue = String(body.signature ?? '');
    const capture = prepareCapture(body, 'verify');
    const liveness = body.livenessEvidence;
    if (!branchId || (mode === 'verify_kiosk' && !employeeId) || deviceId.length < 8 || !challengeId || !signedPayload || !signatureValue || !['blink_turn_left','blink_turn_right','turn_left_blink','turn_right_blink'].includes(challengeAction) || body.livenessPassed !== true || body.captureVersion !== 'challenge_temporal_v5' || !validLivenessEvidence(liveness)) {
      return json({ error: 'A valid live face scan is required' }, 400);
    }
    if (!capture) return json({ matched: false, reason: 'capture_inconsistent' });
    if (!validDescriptor(body.descriptor)) return json({ error: 'Face evidence is incomplete' }, 400);
    const expectedPayload = [challengeId, branchId, deviceId, challengeAction, await descriptorDigest(body.descriptor), canonicalLivenessEvidence(liveness)].join('|');
    if (signedPayload !== expectedPayload) return json({ error: 'Face evidence was altered' }, 403);
    const { data: publicKey, error: keyError } = await admin.database.rpc('trusted_device_public_key', { p_actor_user_id: user.id, p_device_id: deviceId });
    if (keyError || typeof publicKey !== 'string') return json({ error: 'This iPhone is not registered as a trusted device' }, 403);
    try {
      const key = await crypto.subtle.importKey('raw', bytesFromBase64(publicKey), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
      const signature = derSignatureToRaw(bytesFromBase64(signatureValue));
      if (!signature || !(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, Uint8Array.from(signature).buffer, new TextEncoder().encode(signedPayload).buffer))) {
        return json({ error: 'Face evidence signature is invalid' }, 403);
      }
    } catch { return json({ error: 'Face evidence signature could not be verified' }, 403); }
    const { data: challengeConsumed, error: challengeError } = await admin.database.rpc('consume_biometric_challenge', {
      p_challenge_id: challengeId,
      p_actor_user_id: user.id,
      p_branch_id: branchId,
      p_device_id: deviceId,
      p_action: challengeAction
    });
    if (challengeError || challengeConsumed !== true) return json({ matched: false, reason: 'liveness_required' });
    rpcName = mode === 'verify_kiosk' ? 'verify_employee_face_for_kiosk' : 'verify_employee_face';
    args = {
      p_actor_user_id: user.id,
      p_branch_id: branchId,
      p_device_id: deviceId,
      p_model_version: String(body.modelVersion ?? ''),
      p_descriptor: capture.descriptor,
      p_liveness_passed: true
    };
    if (mode === 'verify_kiosk') args.p_employee_id = employeeId;
  } else {
    return json({ error: 'Invalid biometric action' }, 400);
  }

  const { data, error } = await admin.database.rpc(rpcName, args);
  if (error) return json({ error: error.message ?? 'Face verification failed' }, 400);
  if ((mode === 'verify' || mode === 'verify_kiosk') && data && typeof data === 'object' && validLivenessEvidence(body.livenessEvidence)) {
    const proofId = String((data as Record<string, unknown>).proofId ?? '');
    if (proofId) {
      await admin.database.from('face_verification_proofs').update({
        capture_version: 'challenge_temporal_v5',
        liveness_evidence: body.livenessEvidence
      }).eq('id', proofId);
    }
  }
  return json(data);
}
