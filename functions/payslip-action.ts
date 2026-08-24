import { createAdminClient, createClient } from 'npm:@insforge/sdk';
import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*' }
});

const money = (minor: number) => `PKR ${(minor / 100).toLocaleString('en-PK', { minimumFractionDigits: 2 })}`;
const hex = (bytes: Uint8Array) => Array.from(bytes).map((value) => value.toString(16).padStart(2, '0')).join('');

type Run = { id: string; organization_id: string; title: string; period_start: string; period_end: string; status: string; locked_at: string | null };
type Item = { id: string; payroll_run_id: string; employee_id: string; gross_minor: number; deductions_minor: number; net_minor: number; status: string };
type Employee = { id: string; employee_code: string; full_name: string; position: string | null };
type Component = { label: string; component_type: string; amount_minor: number };

async function buildPDF(run: Run, item: Item, employee: Employee, components: Component[]) {
  const document = await PDFDocument.create();
  const page = document.addPage([595, 842]);
  const regular = await document.embedFont(StandardFonts.Helvetica);
  const bold = await document.embedFont(StandardFonts.HelveticaBold);
  const navy = rgb(0.025, 0.105, 0.29);
  const orange = rgb(1, 0.62, 0.04);
  page.drawRectangle({ x: 0, y: 742, width: 595, height: 100, color: navy });
  page.drawText('CB EMPLOYEE HUB', { x: 42, y: 794, size: 22, font: bold, color: rgb(1, 1, 1) });
  page.drawText('Official Payslip', { x: 42, y: 766, size: 12, font: regular, color: orange });
  let y = 705;
  const row = (label: string, value: string, strong = false) => {
    page.drawText(label, { x: 42, y, size: 10, font: regular, color: rgb(0.35, 0.38, 0.44) });
    page.drawText(value, { x: 210, y, size: strong ? 13 : 10, font: strong ? bold : regular, color: navy });
    y -= strong ? 30 : 22;
  };
  row('Employee', employee.full_name, true);
  row('Employee code', employee.employee_code);
  row('Position', employee.position ?? 'Staff');
  row('Payroll', run.title);
  row('Period', `${run.period_start} to ${run.period_end}`);
  y -= 12;
  page.drawText('EARNINGS AND DEDUCTIONS', { x: 42, y, size: 11, font: bold, color: navy });
  y -= 25;
  for (const component of components.slice(0, 18)) {
    page.drawText(component.label, { x: 42, y, size: 9, font: regular, color: navy });
    page.drawText(component.component_type === 'deduction' ? `- ${money(component.amount_minor)}` : money(component.amount_minor), {
      x: 390, y, size: 9, font: regular, color: component.component_type === 'deduction' ? rgb(0.72, 0.15, 0.18) : rgb(0.05, 0.48, 0.3)
    });
    y -= 20;
  }
  y = Math.min(y - 16, 220);
  page.drawRectangle({ x: 35, y: y - 54, width: 525, height: 72, color: rgb(0.95, 0.96, 0.98) });
  page.drawText('Gross', { x: 52, y: y - 4, size: 10, font: regular, color: navy });
  page.drawText(money(item.gross_minor), { x: 52, y: y - 24, size: 12, font: bold, color: navy });
  page.drawText('Deductions', { x: 225, y: y - 4, size: 10, font: regular, color: navy });
  page.drawText(money(item.deductions_minor), { x: 225, y: y - 24, size: 12, font: bold, color: navy });
  page.drawText('Net salary', { x: 400, y: y - 4, size: 10, font: regular, color: navy });
  page.drawText(money(item.net_minor), { x: 400, y: y - 24, size: 14, font: bold, color: orange });
  page.drawText('Generated from a locked payroll record. This document is immutable.', { x: 42, y: 42, size: 8, font: regular, color: rgb(0.45, 0.48, 0.54) });
  return document.save();
}

export default async function payslipAction(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const baseUrl = Deno.env.get('INSFORGE_BASE_URL');
  const apiKey = Deno.env.get('API_KEY');
  if (!baseUrl || !apiKey) return json({ error: 'Backend is not configured' }, 503);
  const admin = createAdminClient({ baseUrl, apiKey });
  let requestedRunId: string | null = null;
  let scheduled = false;
  try {
    const body = await req.json();
    requestedRunId = body?.runId ? String(body.runId) : null;
  } catch { /* empty scheduled body is accepted */ }
  const dispatchSecret = Deno.env.get('PUSH_DISPATCH_SECRET');
  if (dispatchSecret && req.headers.get('x-dispatch-secret') === dispatchSecret) {
    scheduled = true;
  } else {
    const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
    if (!token) return json({ error: 'Unauthorized' }, 401);
    const userClient = createClient({ baseUrl, accessToken: token });
    const { data: userData } = await userClient.auth.getCurrentUser();
    const userId = userData?.user?.id;
    if (!userId || !requestedRunId) return json({ error: 'A payroll run is required' }, 400);
    const { data: runs } = await admin.database.from('payroll_runs').select('organization_id').eq('id', requestedRunId).limit(1);
    const organizationId = runs?.[0]?.organization_id;
    const { data: memberships } = await userClient.database.from('organization_memberships').select('id').eq('organization_id', organizationId).eq('role', 'owner').eq('is_active', true).limit(1);
    if (!memberships?.length) return json({ error: 'Owner access required' }, 403);
  }

  let runQuery = admin.database.from('payroll_runs').select('id,organization_id,title,period_start,period_end,status,locked_at').eq('status', 'locked');
  if (requestedRunId) runQuery = runQuery.eq('id', requestedRunId);
  const { data: runs, error: runError } = await runQuery.limit(scheduled ? 20 : 1);
  if (runError) return json({ error: runError.message }, 500);
  let generated = 0;
  let skipped = 0;
  for (const run of (runs ?? []) as Run[]) {
    const { data: items, error: itemError } = await admin.database.from('payroll_items').select('id,payroll_run_id,employee_id,gross_minor,deductions_minor,net_minor,status').eq('payroll_run_id', run.id).limit(1000);
    if (itemError) return json({ error: itemError.message }, 500);
    for (const item of (items ?? []) as Item[]) {
      const { data: existing } = await admin.database.from('payslip_documents').select('id').eq('payroll_item_id', item.id).limit(1);
      if (existing?.length) { skipped += 1; continue; }
      const { data: employees } = await admin.database.from('employees').select('id,employee_code,full_name,position').eq('id', item.employee_id).limit(1);
      const employee = employees?.[0] as Employee | undefined;
      if (!employee) { skipped += 1; continue; }
      const { data: components } = await admin.database.from('payroll_item_components').select('label,component_type,amount_minor').eq('payroll_item_id', item.id).order('created_at', { ascending: true }).limit(100);
      const componentRows = (components ?? []) as Component[];
      const bytes = await buildPDF(run, item, employee, componentRows);
      const pdfBuffer = Uint8Array.from(bytes).buffer;
      const digest = hex(new Uint8Array(await crypto.subtle.digest('SHA-256', pdfBuffer)));
      const path = `${run.organization_id}/${item.employee_id}/${item.id}-v1.pdf`;
      const { error: uploadError } = await admin.storage.from('payslips').upload(path, new Blob([pdfBuffer], { type: 'application/pdf' }));
      if (uploadError) return json({ error: uploadError.message ?? 'Payslip upload failed' }, 500);
      const snapshot = { run, item, employee, components: componentRows, issuedAt: new Date().toISOString() };
      const { error: insertError } = await admin.database.from('payslip_documents').insert([{
        organization_id: run.organization_id, payroll_item_id: item.id, employee_id: item.employee_id,
        storage_path: path, generated_by: null, version: 1, snapshot, content_sha256: digest,
        content_type: 'application/pdf', file_size_bytes: bytes.length, payroll_locked_at: run.locked_at
      }]);
      if (insertError) {
        await admin.storage.from('payslips').remove(path);
        return json({ error: insertError.message ?? 'Payslip record failed' }, 500);
      }
      generated += 1;
    }
  }
  return json({ generated, skipped, runs: runs?.length ?? 0 });
}
