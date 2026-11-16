-- محل سوريا (Ahmad Al Khayat Jewellery, USD): merge the duplicate trader «محل احمد الخياط الشارقة»
-- into «احمد الخياط - الشارقة» (بشار 2026-11-16), then remove the duplicate.
-- The duplicate has one movement: TOUT-000004 (إخراج بضاعة — باركود 000273 حلق, 6.28 g).
-- Run the whole file at once in the Supabase SQL editor. It stops without changing anything if the
-- names don't match or if anything is still linked to the duplicate before it is removed.

begin;

do $$
declare
  dup  uuid := '4c7563d7-58b6-428b-bf3a-6670ca24e8f5'; -- محل احمد الخياط الشارقة
  keep uuid := '681f65f0-3227-4a77-9930-fbbe607282ae'; -- احمد الخياط - الشارقة
  st   uuid := 'a15f496a-a4b5-4388-b304-5397eaeeda1b';
  n int;
begin
  if not exists (select 1 from traders where id = dup and store_id = st and name = 'محل احمد الخياط الشارقة')
     or not exists (select 1 from traders where id = keep and store_id = st and name = 'احمد الخياط - الشارقة') then
    raise exception 'الأسماء لا تطابق — لم يتغيّر شيء';
  end if;

  -- 1) move everything that points at the duplicate to the main account
  update trader_movements set trader_id = keep where trader_id = dup;
  update invoices         set trader_id = keep where trader_id = dup;
  update gold_stock_lots  set trader_id = keep where trader_id = dup;
  update diamond_stock_lots set trader_id = keep where trader_id = dup;

  -- 2) nothing may be left on the duplicate (its movements would be deleted with it)
  select (select count(*) from trader_movements where trader_id = dup)
       + (select count(*) from invoices where trader_id = dup)
       + (select count(*) from gold_stock_lots where trader_id = dup)
       + (select count(*) from diamond_stock_lots where trader_id = dup) into n;
  if n > 0 then raise exception 'ما زال % سجل مرتبطاً بالحساب المكرر — لم يُحذف شيء', n; end if;

  -- 3) remove the empty duplicate
  delete from traders where id = dup;
end $$;

-- check: the main account now has 25 movements, the duplicate is gone
select t.name, (select count(*) from trader_movements m where m.trader_id = t.id) as movements
  from traders t where t.store_id = 'a15f496a-a4b5-4388-b304-5397eaeeda1b' and t.name like '%الشارقة%';

commit;
