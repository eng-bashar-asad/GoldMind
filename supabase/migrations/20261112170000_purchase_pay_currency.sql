-- Purchases in another currency (Bashar 2026-11-12: buy scrap from individuals in SYP, not USD).
-- Like a sale: the invoice is kept in the shop's currency and carries pay_currency + pay_fx_rate
-- (units of pay_currency per 1 unit of the shop's currency). mirror_invoice_cash_to_daily already
-- turns the cash payment into a daily-box row in pay_currency. Patched in place like 20261102160000.
do $mig$
declare d text; n text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'post_purchase_invoice';
  if position('pay_fx_rate' in d) = 0 then
    n := replace(d, '  me uuid; inv_id uuid; inv_no text; ex record;',
      E'  me uuid; inv_id uuid; inv_no text; ex record;\n  pcur text := nullif(upper(trim(p->>''pay_currency'')), '''');\n  prate numeric := nullif(p->>''pay_fx_rate'', '''')::numeric;');
    n := replace(n, '  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;',
      E'  if pcur is not null then\n    if pcur !~ ''^[A-Z]{3}$'' then raise exception ''رمز عملة غير صحيح''; end if;\n    if pcur = (select upper(coalesce(currency, ''AED'')) from stores where id = sid) then pcur := null; prate := null;\n    elsif prate is null or prate <= 0 then raise exception ''أدخل سعر صرف صحيحاً لعملة %'', pcur; end if;\n  else prate := null; end if;\n  select id into me from staff where user_id = auth.uid() and store_id = sid limit 1;');
    n := replace(n, '      created_by, client_ref)', '      created_by, client_ref, pay_currency, pay_fx_rate)');
    n := replace(n, '      nullif(p->>''attachment_url'', ''''), photos, me, ref)', '      nullif(p->>''attachment_url'', ''''), photos, me, ref, pcur, prate)');
    if n = d or position('pcur, prate)' in n) = 0 or position('pay_currency, pay_fx_rate)' in n) = 0 then
      raise exception 'post_purchase_invoice: patch did not apply';
    end if;
    execute n;
  end if;
end $mig$;
