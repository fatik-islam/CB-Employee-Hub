import { createAdminClient } from 'npm:@insforge/sdk';

type PushRow = {
  notification_id: string;
  user_id: string;
  title: string;
  message: string;
  category: string;
  token: string;
  environment: 'development' | 'production';
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'content-type': 'application/json' }
});

const base64url = (bytes: Uint8Array) => {
  let binary = '';
  bytes.forEach((value) => { binary += String.fromCharCode(value); });
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/g, '');
};

const encodeJson = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));

let cachedJwt: { value: string; createdAt: number } | null = null;

async function providerToken(teamId: string, keyId: string, privateKey: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.createdAt < 45 * 60) return cachedJwt.value;
  const pem = privateKey.replaceAll('\\n', '\n').replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  const binary = Uint8Array.from(atob(pem), (character) => character.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', binary, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const unsigned = `${encodeJson({ alg: 'ES256', kid: keyId })}.${encodeJson({ iss: teamId, iat: now })}`;
  const signature = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned)));
  cachedJwt = { value: `${unsigned}.${base64url(signature)}`, createdAt: now };
  return cachedJwt.value;
}

export default async function pushDispatch(req: Request): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const dispatchSecret = Deno.env.get('PUSH_DISPATCH_SECRET');
  if (!dispatchSecret || req.headers.get('x-dispatch-secret') !== dispatchSecret) return json({ error: 'Unauthorized' }, 401);

  const baseUrl = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey = Deno.env.get('API_KEY');
  const teamId = Deno.env.get('APNS_TEAM_ID');
  const keyId = Deno.env.get('APNS_KEY_ID');
  const privateKey = Deno.env.get('APNS_PRIVATE_KEY');
  const topic = Deno.env.get('APNS_BUNDLE_ID') ?? 'pk.com.chickybites.employeehub';
  if (!baseUrl || !apiKey || !teamId || !keyId || !privateKey) return json({ error: 'APNs is not configured' }, 503);

  const admin = createAdminClient({ baseUrl, apiKey });
  const { data, error } = await admin.database.rpc('claim_push_notification_batch', { p_limit: 50 });
  if (error) return json({ error: error.message ?? 'Could not claim notifications' }, 500);
  const rows = (data ?? []) as PushRow[];
  if (!rows.length) return json({ claimed: 0, sent: 0, failed: 0 });

  const authorization = await providerToken(teamId, keyId, privateKey);
  let sent = 0;
  let failed = 0;
  for (const row of rows) {
    const host = row.environment === 'development' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    const response = await fetch(`https://${host}/3/device/${encodeURIComponent(row.token)}`, {
      method: 'POST',
      headers: {
        authorization: `bearer ${authorization}`,
        'apns-topic': topic,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        aps: { alert: { title: row.title, body: row.message }, sound: 'default', 'thread-id': row.category },
        notificationId: row.notification_id,
        category: row.category
      })
    });
    if (response.ok) {
      sent += 1;
      await admin.database.rpc('complete_push_notification', { p_notification_id: row.notification_id, p_sent: true, p_error: null });
    } else {
      failed += 1;
      const reason = (await response.text()).slice(0, 500);
      await admin.database.rpc('complete_push_notification', { p_notification_id: row.notification_id, p_sent: false, p_error: `${response.status}: ${reason}` });
      if ([400, 410].includes(response.status) && /BadDeviceToken|DeviceTokenNotForTopic|Unregistered/.test(reason)) {
        await admin.database.rpc('deactivate_mobile_push_token', { p_token: row.token });
      }
    }
  }
  return json({ claimed: rows.length, sent, failed });
}
