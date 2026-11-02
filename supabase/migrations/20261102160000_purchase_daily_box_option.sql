-- Purchases: «يدخل إلى الصندوق اليومي» option, like the receipt/payment vouchers (Bashar 2026-11-02).
-- Unticked: the purchase's cash still leaves the main box (cash_movements), but no row is written in the
-- daily box. Sales are unchanged. Applied on 2026-11-02 by patching the two live functions in place.
alter table public.invoices add column if not exists skip_daily boolean not null default false;
comment on column public.invoices.skip_daily is 'Purchase whose cash payment is NOT entered in the daily box (chosen on the purchase screen). mirror_invoice_cash_to_daily skips it.';

do $do$
declare d text; n text;
begin
  -- cash_movements -> daily box mirror: skip invoices marked skip_daily (also their later edits/cancel)
  d := pg_get_functiondef('public.mirror_invoice_cash_to_daily'::regproc);
  if position('inv.skip_daily' in d) = 0 then
    n := replace(d, 'select id, type, payment_method, pay_breakdown, pay_currency, pay_fx_rate into inv from public.invoices',
                    'select id, type, payment_method, pay_breakdown, pay_currency, pay_fx_rate, skip_daily into inv from public.invoices');
    n := replace(n, 'if inv is null then return new; end if;', 'if inv is null or inv.skip_daily then return new; end if; -- purchase kept out of the daily box');
    if n = d then raise exception 'mirror patch failed'; end if;
    execute n;
  end if;
  -- post_purchase_invoice: p.daily = false marks the invoice before its cash movement is written
  d := pg_get_functiondef('public.post_purchase_invoice'::regproc);
  if position('skip_daily' in d) = 0 then
    n := replace(d, E'  if pm = ''cash'' and total > 0 then\n    insert into cash_movements',
      E'  -- «يدخل إلى الصندوق اليومي» unticked: the cash still leaves the main box, the daily box is left alone\n  if not coalesce((p->>''daily'')::boolean, true) then update invoices set skip_daily = true where id = inv_id; end if;\n  if pm = ''cash'' and total > 0 then\n    insert into cash_movements');
    if n = d then raise exception 'purchase patch failed'; end if;
    execute n;
  end if;
end $do$;
