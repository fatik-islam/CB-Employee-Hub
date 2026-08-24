create or replace function public.record_salary_payment(p_payroll_item_id uuid,p_amount_minor bigint,p_method text,p_reference text,p_paid_on date)
returns public.salary_payments
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare item public.payroll_items%rowtype; run public.payroll_runs%rowtype; payment public.salary_payments%rowtype; paid_total bigint;
begin
  if p_amount_minor<=0 then raise exception 'payment amount must be positive'; end if;
  if p_method not in ('cash','bank_transfer','cheque','other') then raise exception 'invalid payment method'; end if;
  select * into item from public.payroll_items where id=p_payroll_item_id for update;
  if item.id is null then raise exception 'payroll item not found'; end if;
  select * into run from public.payroll_runs where id=item.payroll_run_id;
  if not public.can_manage_payroll(run.organization_id) then raise exception 'not permitted'; end if;
  if run.status not in ('approved','locked') or item.status not in ('approved','paid') then raise exception 'payroll is not approved'; end if;
  select coalesce(sum(amount_minor),0) into paid_total from public.salary_payments where payroll_item_id=item.id;
  if paid_total+p_amount_minor>item.net_minor then raise exception 'payment exceeds net salary'; end if;
  insert into public.salary_payments(organization_id,payroll_item_id,amount_minor,currency,payment_method,reference,paid_on,recorded_by)
    values(run.organization_id,item.id,p_amount_minor,run.currency,p_method,nullif(trim(p_reference),''),p_paid_on,auth.uid()) returning * into payment;
  if paid_total+p_amount_minor=item.net_minor then update public.payroll_items set status='paid' where id=item.id; end if;
  insert into public.audit_events(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(run.organization_id,run.branch_id,auth.uid(),'salary.payment_recorded','payroll_item',item.id,jsonb_build_object('payment_id',payment.id,'amount_minor',p_amount_minor,'method',p_method));
  return payment;
end;
$$;
revoke insert on public.salary_payments from authenticated;
revoke all on function public.record_salary_payment(uuid,bigint,text,text,date) from public,anon;
grant execute on function public.record_salary_payment(uuid,bigint,text,text,date) to authenticated;
