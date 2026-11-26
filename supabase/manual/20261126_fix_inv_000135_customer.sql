-- محل الشارقة (a15f496a…): INV-2026-000135 (1950 USD) was entered on «علاء العوا» by mistake and
-- changed to «علي جبيلي» on 2026-11-26. The 1950 payment of 2026-11-21 was علي's too (بشار 2026-11-26).
-- Result after this file: the invoice, its debt and the 2026-11-21 payment all sit on علي جبيلي,
-- both customers' balances are back to what they were (0), and «فحص الحسابات» shows no warning.
-- Run the whole file at once in the Supabase SQL editor. It stops without changing anything
-- if the rows are not exactly the ones expected.

begin;

do $$
declare
  st   uuid := 'a15f496a-a4b5-4388-b304-5397eaeeda1b';
  inv  uuid := 'b69325af-6103-472f-b191-544ad583c23c';  -- INV-2026-000135
  ala  uuid := 'a78aeea1-f380-4a9b-ac54-a1250636a0f7';  -- علاء العوا
  ali  uuid := 'aa86b95f-f81a-4fac-b4f8-b0f772284ba2';  -- علي جبيلي
  moved uuid[] := array['2429e087-ea01-4fdd-b45e-3493956aa1dd',   -- sale debt 21/11
                        'f12128f9-4c11-4678-bbdc-4ca054bf8792',   -- payment 21/11
                        'f6aff2e5-1ef7-42a4-b4f7-39a9b5177598',   -- allocation to the invoice
                        'f3e76f4e-5710-48b1-8b45-748d3387e3cf']::uuid[]; -- allocation pair
  undo  uuid[] := array['388eb645-afb1-432b-8905-2482c95edb50',   -- 26/11 change-customer rows
                        'dc52377a-d73d-4367-9e95-e8a0e14b6e86',
                        '4118c4a2-8d93-4cd4-8367-2c75ad75b6c3',
                        '6fec8f48-d408-4dec-9d3c-23de1e3ccfab']::uuid[];
  n int;
begin
  if not exists (select 1 from invoices where id = inv and store_id = st and customer_id = ali and total_amount = 1950)
     or not exists (select 1 from customers where id = ala and name = 'علاء العوا')
     or not exists (select 1 from customers where id = ali and name = 'علي جبيلي') then
    raise exception 'الفاتورة أو الأسماء لا تطابق — لم يتغيّر شيء';
  end if;
  select count(*) into n from customer_debts where id = any(moved) and customer_id = ala and cash_amount = 1950;
  if n <> 4 then raise exception 'حركات 21/11 لا تطابق (%) — لم يتغيّر شيء', n; end if;
  select count(*) into n from customer_debts where id = any(undo) and cash_amount = 1950 and store_id = st;
  if n <> 4 then raise exception 'حركات 26/11 لا تطابق (%) — لم يتغيّر شيء', n; end if;

  -- 1) the 26/11 change-customer rows cancel each other out once the old rows move to علي
  delete from customer_debts where id = any(undo);

  -- 2) the sale debt, the payment and its allocation move to علي
  update customer_debts set customer_id = ali where id = any(moved);
  update cash_movements set description = 'دفعة من العميل علي جبيلي'
   where id = 'e25f61b0-eb92-47b9-aca2-3832b4175887' and description = 'دفعة من العميل علاء العوا';

  -- 3) the invoice stays fully paid
  update invoices set amount_paid = 1950, status = 'paid' where id = inv;
end $$;

commit;

-- check: both balances 0, and the invoice's debt rows add up to 0
select c.name, sum(case when d.movement_type = 'debt_increase' then d.cash_amount else -d.cash_amount end) as balance
  from customer_debts d join customers c on c.id = d.customer_id
 where c.id in ('a78aeea1-f380-4a9b-ac54-a1250636a0f7', 'aa86b95f-f81a-4fac-b4f8-b0f772284ba2')
 group by c.name;
