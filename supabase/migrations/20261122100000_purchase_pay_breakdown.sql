-- Purchase paid in cash with several currencies (بشار 2026-11-22: scrap or anything else).
-- post_purchase_invoice takes p.pay_breakdown = [{currency, amount, rate}] (rate: units per 1
-- shop-currency unit), checks it adds up to the invoice total and stores it on the invoice.
-- The main box takes the total out in the shop's currency as before; the daily-box mirror
-- (mirror_invoice_cash_to_daily) already splits an invoice with a pay_breakdown into one row
-- per currency. Patched in place so the rest of the function stays exactly as it is.
do $mig$
declare d text := pg_get_functiondef('public.post_purchase_invoice'::regproc); n text;
begin
  n := replace(d, $a$prate numeric := nullif(p->>'pay_fx_rate', '')::numeric;$a$,
    $a$prate numeric := nullif(p->>'pay_fx_rate', '')::numeric;
  bd jsonb := case when jsonb_typeof(p->'pay_breakdown') = 'array' and jsonb_array_length(p->'pay_breakdown') > 0 then p->'pay_breakdown' end;
  bd_sum numeric;$a$);
  if n = d then raise exception 'post_purchase_invoice: declare anchor not found'; end if; d := n;

  n := replace(d, $a$  total := round(total, 2);
$a$, $a$  total := round(total, 2);
  if bd is not null then
    if pm <> 'cash' then bd := null;
    else
      if exists (select 1 from jsonb_array_elements(bd) b
                  where upper(coalesce(b->>'currency', '')) !~ '^[A-Z]{3}$'
                     or coalesce(nullif(b->>'amount', '')::numeric, 0) <= 0
                     or coalesce(nullif(b->>'rate', '')::numeric, 0) <= 0) then
        raise exception 'سطر غير صحيح في الدفع بعدة عملات (العملة والمبلغ وسعر الصرف مطلوبة)';
      end if;
      select sum((b->>'amount')::numeric / (b->>'rate')::numeric) into bd_sum from jsonb_array_elements(bd) b;
      if abs(bd_sum - total) >= 0.05 then
        raise exception 'مجموع المبالغ بالعملات (%) لا يساوي إجمالي الفاتورة (%)', round(bd_sum, 2), total;
      end if;
      select jsonb_agg(jsonb_build_object('currency', upper(b->>'currency'), 'amount', round((b->>'amount')::numeric, 2),
                                          'rate', (b->>'rate')::numeric, 'method', 'cash'))
        into bd from jsonb_array_elements(bd) b;
    end if;
  end if;
$a$);
  if n = d then raise exception 'post_purchase_invoice: total anchor not found'; end if; d := n;

  n := replace(d, $a$created_by, client_ref, pay_currency, pay_fx_rate)$a$, $a$created_by, client_ref, pay_currency, pay_fx_rate, pay_breakdown)$a$);
  if n = d then raise exception 'post_purchase_invoice: column anchor not found'; end if; d := n;
  n := replace(d, $a$me, ref, pcur, prate)$a$, $a$me, ref, pcur, prate, bd)$a$);
  if n = d then raise exception 'post_purchase_invoice: values anchor not found'; end if; d := n;

  execute d;
end $mig$;
