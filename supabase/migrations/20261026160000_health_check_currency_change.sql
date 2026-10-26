-- فحص الحسابات: currency-change movements of an invoice («تعديل عملات الدفع …») are not mirrored
-- into the daily box on purpose (gm_invoice_daily_rewrite sets the invoice's own rows), so the
-- "daily_box_missing" warning skips them. Applied by patching accounting_health_check in place:
--   and not coalesce(cm.edit_delta, false)
--   and coalesce(cm.description, '') not like 'تعديل عملات الدفع%'
--   and not exists (select 1 from daily_cash_log l where l.cash_movement_id = cm.id);
do $$
declare d text; old text := $x$    and not coalesce(cm.edit_delta, false)
    and not exists (select 1 from daily_cash_log l where l.cash_movement_id = cm.id);$x$;
begin
  select pg_get_functiondef('public.accounting_health_check'::regproc) into d;
  if position(old in d) = 0 then return; end if;
  d := replace(d, old, $y$    and not coalesce(cm.edit_delta, false)
    and coalesce(cm.description, '') not like 'تعديل عملات الدفع%' -- currency changes: the invoice's own rows are rewritten
    and not exists (select 1 from daily_cash_log l where l.cash_movement_id = cm.id);$y$);
  execute d;
end $$;
