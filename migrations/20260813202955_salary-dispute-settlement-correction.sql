-- Preserve the correct pre-dispute state and settle already-applied disputes by
-- an explicit reversing transaction, without mutating historical amounts.

create or replace function public.resolve_salary_dispute(p_dispute_id uuid,p_status text,p_note text)
returns public.salary_transaction_disputes language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare
  dispute_row public.salary_transaction_disputes%rowtype;
  transaction_row public.salary_ledger_transactions%rowtype;
  reversal_row public.salary_ledger_transactions%rowtype;
  previous_status text;
  final_status text;
begin
  select d.* into dispute_row from public.salary_transaction_disputes d where d.id=p_dispute_id for update;
  if dispute_row.id is null or not public.can_approve_payroll(dispute_row.organization_id) or dispute_row.status not in ('open','under_review') then raise exception 'not permitted'; end if;
  if p_status not in ('accepted','rejected') then raise exception 'invalid resolution'; end if;
  select t.* into transaction_row from public.salary_ledger_transactions t where t.id=dispute_row.transaction_id for update;
  select e.from_status into previous_status
  from public.salary_transaction_events e
  where e.transaction_id=transaction_row.id and e.event_type='disputed'
  order by e.created_at desc limit 1;
  previous_status:=coalesce(previous_status,'approved');

  update public.salary_transaction_disputes
  set status=p_status,resolution_note=trim(p_note),reviewed_by=auth.uid(),reviewed_at=now()
  where id=dispute_row.id returning * into dispute_row;

  if p_status='accepted' and (previous_status in ('applied','paid') or transaction_row.payroll_item_id is not null) then
    if exists(select 1 from public.salary_ledger_transactions r where r.reversal_of_id=transaction_row.id) then raise exception 'transaction already reversed'; end if;
    update public.salary_ledger_transactions set status='reversed' where id=transaction_row.id;
    insert into public.salary_ledger_transactions(
      organization_id,branch_id,employee_id,rule_id,reversal_of_id,transaction_type,category,label,description,
      amount_minor,status,occurred_at,work_date,source_type,source_id,created_by,approved_by,approved_at
    ) values(
      transaction_row.organization_id,transaction_row.branch_id,transaction_row.employee_id,transaction_row.rule_id,transaction_row.id,
      case when transaction_row.transaction_type='deduction' then 'earning' else 'deduction' end,
      transaction_row.category,'Reversal: '||transaction_row.label,trim(p_note),transaction_row.amount_minor,
      'approved',now(),current_date,'reversal',transaction_row.id,auth.uid(),auth.uid(),now()
    ) returning * into reversal_row;
    insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note)
    values(transaction_row.organization_id,transaction_row.id,'dispute_resolved','disputed','reversed',trim(p_note));
    insert into public.salary_transaction_events(organization_id,transaction_id,event_type,to_status,note)
    values(transaction_row.organization_id,reversal_row.id,'created','approved','Dispute settlement for '||transaction_row.id);
  else
    final_status:=case when p_status='accepted' then 'rejected' else previous_status end;
    update public.salary_ledger_transactions
    set status=final_status,
        approved_by=case when final_status in ('approved','applied','paid') then coalesce(transaction_row.approved_by,auth.uid()) else null end,
        approved_at=case when final_status in ('approved','applied','paid') then coalesce(transaction_row.approved_at,now()) else null end
    where id=transaction_row.id;
    insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note)
    values(transaction_row.organization_id,transaction_row.id,'dispute_resolved','disputed',final_status,trim(p_note));
  end if;
  return dispute_row;
end;
$$;

create or replace function public.release_salary_ledger_payroll_item()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
  with released as (
    update public.salary_ledger_transactions
    set payroll_item_id=null,applied_at=null,
        status=case when source_type='payroll_component' then 'reversed' else 'approved' end
    where payroll_item_id=old.id and status in ('applied','paid')
    returning organization_id,id,source_type
  )
  insert into public.salary_transaction_events(organization_id,transaction_id,event_type,from_status,to_status,note,actor_user_id)
  select organization_id,id,'recalculated','applied',case when source_type='payroll_component' then 'reversed' else 'approved' end,
         'Payroll draft was recalculated.',auth.uid()
  from released;
  return old;
end;
$$;
