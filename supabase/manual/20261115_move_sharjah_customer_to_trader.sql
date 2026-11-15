-- ينقل الـ 25,000 USD من الزبون «احمد الخياط - الشارقة» إلى التاجر «احمد الخياط - الشارقة» ثم يحذف الزبون.
-- الحركة الأصلية: «صرف للعميل» 25,000 بتاريخ 14/10/2026 — تُسجّل على التاجر كـ «صرف كاش للتاجر» بنفس التاريخ،
-- فيصير التاجر مديوناً للمحل بها. حركة الصندوق الأصلية تبقى كما هي (المال خرج فعلاً).
begin;

insert into public.trader_movements (store_id, trader_id, movement_type, weight_grams, karat, gold_24k_equivalent, fab_fee_amount, source, notes, created_at)
select d.store_id, '681f65f0-3227-4a77-9930-fbbe607282ae', 'debt_decrease', 0, null, 0, d.cash_amount, 'cash_out',
       'صرف كاش للتاجر — منقول من حساب الزبون «احمد الخياط - الشارقة»', d.created_at
  from public.customer_debts d
 where d.customer_id = '7f2c786e-0b8b-4a72-9402-5018f05dc618' and d.source = 'cash_out' and d.cash_amount = 25000;

-- حذف الزبون (وحركة دينه الوحيدة معه)
delete from public.customers where id = '7f2c786e-0b8b-4a72-9402-5018f05dc618' and name = 'احمد الخياط - الشارقة';

commit;
