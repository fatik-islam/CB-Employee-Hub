import { createAdminClient } from 'npm:@insforge/sdk';

const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'content-type': 'application/json' }
});

export default async function operationsAutomation(req: Request): Promise<Response> {
  if (req.method !== 'POST') return response({ error: 'Method not allowed' }, 405);
  const secret = Deno.env.get('PUSH_DISPATCH_SECRET');
  if (!secret || req.headers.get('x-dispatch-secret') !== secret) return response({ error: 'Unauthorized' }, 401);
  const baseUrl = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey = Deno.env.get('API_KEY');
  if (!baseUrl || !apiKey) return response({ error: 'Backend is not configured' }, 503);
  const runDate = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit'
  }).format(new Date());
  const admin = createAdminClient({ baseUrl, apiKey });
  const { data: accrual, error: accrualError } = await admin.database.rpc('run_leave_accruals', { p_run_date: runDate });
  if (accrualError) return response({ error: accrualError.message ?? 'Leave accrual failed' }, 500);
  const { data: reminders, error: remindersError } = await admin.database.rpc('enqueue_operational_reminders', { p_run_date: runDate });
  if (remindersError) return response({ error: remindersError.message ?? 'Reminder generation failed' }, 500);
  const { data: maintenance, error: maintenanceError } = await admin.database.rpc('run_production_maintenance', { p_run_date: runDate });
  if (maintenanceError) return response({ error: maintenanceError.message ?? 'Production maintenance failed' }, 500);
  return response({ runDate, accrual, reminders, maintenance });
}
