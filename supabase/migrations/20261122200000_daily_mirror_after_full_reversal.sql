-- PINV-2026-000048: edited down to 0 (the daily box got an "in" row for the full reversal), then
-- cancelled / restored, then edited up to 5100 — that last delta was added onto the original
-- 21 Nov row (4325 + 5100 = 9425) while the 4325 "in" row stayed on 22 Nov.
-- Rule now: once an invoice's daily rows already carry a separate edit row in that currency
-- (the original row was fully offset), later edit deltas get their own row too — the original
-- row is only adjusted in place while it still stands alone.
do $mig$
declare d text := pg_get_functiondef('public.mirror_invoice_cash_to_daily'::regproc); n text;
begin
  n := replace(d, $a$    if r.id is not null then
      full_base := round(r.amount + case when new.direction = r.direction then amt else -amt end, 2);$a$,
  $a$    -- already offset by its own edit row: this delta gets its own row as well
    if r.id is not null and not exists (select 1 from daily_cash_log l2 join cash_movements m2 on m2.id = l2.cash_movement_id
                                         where m2.invoice_id = inv.id and m2.edit_delta and m2.id <> new.id
                                           and upper(l2.currency) = upper(cur)) then
      full_base := round(r.amount + case when new.direction = r.direction then amt else -amt end, 2);$a$);
  if n = d then raise exception 'mirror_invoice_cash_to_daily: anchor not found'; end if;
  execute n;
end $mig$;
