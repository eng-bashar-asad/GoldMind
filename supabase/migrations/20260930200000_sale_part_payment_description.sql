-- A part-paid sale's cashbox line names only what was used ("3000.00 نقداً"),
-- not "3000.00 نقدي + 0.00 فيزا/بنك".
do $mig$
declare d text; n text;
begin
  d := pg_get_functiondef('post_sale_invoice'::regproc);
  n := replace(d,
    $a$format('تحصيل جزئي لفاتورة بيع %s (%s نقدي + %s فيزا/بنك)', inv_no, cash_amt, bank_amt)$a$,
    $b$format('تحصيل جزئي لفاتورة بيع %s (%s)', inv_no, concat_ws(' + ', case when cash_amt > 0 then cash_amt || ' نقداً' end, case when bank_amt > 0 then bank_amt || ' فيزا/بنك' end))$b$);
  if n = d then raise exception 'pattern not found'; end if;
  execute n;
end $mig$;
