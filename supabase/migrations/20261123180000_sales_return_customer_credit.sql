-- Sales return: the refund may stay on the customer's account as credit (عربون) instead of
-- leaving the box (بشار 2026-11-23). refund_method 'customer_credit': no cash movement, a
-- debt_decrease tagged source 'return_credit' — the customer's balance goes into credit and the
-- next sale uses it like any deposit. Patched in place; the rest of the function is unchanged.
do $mig$
declare d text := pg_get_functiondef('public.post_sales_return'::regproc); n text;
begin
  n := replace(d, $a$if rm is null or rm not in ('cash', 'bank', 'debt_reduce') then$a$,
                  $a$if rm is null or rm not in ('cash', 'bank', 'debt_reduce', 'customer_credit') then$a$);
  if n = d then raise exception 'post_sales_return: method anchor not found'; end if; d := n;

  n := replace(d, $a$if rm = 'debt_reduce' and o.customer_id is null then raise exception 'لا يوجد عميل لتخفيض دينه'; end if;$a$,
                  $a$if rm = 'debt_reduce' and o.customer_id is null then raise exception 'لا يوجد عميل لتخفيض دينه'; end if;
  if rm = 'customer_credit' and o.customer_id is null then raise exception 'الفاتورة بلا عميل — لا يوجد حساب يبقى فيه المبلغ'; end if;$a$);
  if n = d then raise exception 'post_sales_return: customer anchor not found'; end if; d := n;

  n := replace(d, $a$case when rm = 'debt_reduce' then 'credit' else rm end$a$,
                  $a$case when rm in ('debt_reduce', 'customer_credit') then 'credit' else rm end$a$);
  if n = d then raise exception 'post_sales_return: payment anchor not found'; end if; d := n;

  n := replace(d, $a$  elsif total > 0 then
    insert into cash_movements$a$,
  $a$  elsif rm = 'customer_credit' then
    if total > 0 then
      insert into customer_debts (store_id, customer_id, invoice_id, movement_type, cash_amount, gold_grams_24k, notes, created_by, source)
        values (sid, o.customer_id, inv_id, 'debt_decrease', total, 0, note || ' — رصيد للعميل (عربون)', me, 'return_credit');
    end if;
  elsif total > 0 then
    insert into cash_movements$a$);
  if n = d then raise exception 'post_sales_return: refund anchor not found'; end if; d := n;

  execute d;
end $mig$;
