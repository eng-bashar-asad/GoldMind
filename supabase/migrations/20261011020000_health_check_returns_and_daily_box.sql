-- Accounting health check:
-- 1) "sold piece still available" no longer fires for pieces taken back by a sales return or an
--    exchange (they are rightly back in stock), nor for the negative (returned) lines of an exchange.
-- 2) new: an invoice payment that reached the cash movements but not the daily cash box
--    (payments since 2026-08-08, when the daily box started mirroring invoices).
CREATE OR REPLACE FUNCTION public.accounting_health_check(sid uuid)
 RETURNS TABLE(severity text, code text, title text, details text, ref_id uuid, ref_label text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare scur text;
begin
  if not (has_permission('view_reports', sid)) then
    raise exception 'ليس لديك صلاحية' using errcode = '42501';
  end if;
  select upper(coalesce(nullif(currency,''),'AED')) into scur from stores where id = sid;

  return query
  select 'error', 'gold_price_currency', 'سعر الذهب لا يتناسب مع عملة المحل',
         gold_price_problem(sid, g.karat, g.price_per_gram), null::uuid, g.karat || 'K'
  from gold_prices g where g.store_id = sid and gold_price_problem(sid, g.karat, g.price_per_gram) is not null;

  return query
  select 'warning', 'invoice_currency', 'فاتورة بعملة غير عملة المحل',
         format('الفاتورة بـ %s والمحل بـ %s', i.currency, scur), i.id, i.invoice_number
  from invoices i where i.store_id = sid and i.currency is not null and upper(i.currency) <> scur and i.status <> 'cancelled';

  return query
  select 'error', 'invoice_lines_total', 'مجموع سطور الفاتورة ≠ الإجمالي',
         format('السطور %s — الإجمالي %s', coalesce(x.s, 0), i.total_amount), i.id, i.invoice_number
  from invoices i left join lateral (select sum(line_total) s, count(*) n from invoice_items where invoice_id = i.id) x on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled'
    and (x.n = 0 or abs(coalesce(x.s, 0) - i.total_amount) > 0.01);

  return query
  select 'warning', 'invoice_cash_mismatch', 'المقبوض بالفاتورة ≠ المسجّل بالصندوق والدفعات',
         format('مدفوع %s — بالصندوق %s — دفعات لاحقة %s', i.amount_paid, coalesce(c.s, 0), coalesce(al.s, 0)), i.id, i.invoice_number
  from invoices i
  left join lateral (select sum(case when direction = 'in' then amount else -amount end) s from cash_movements where invoice_id = i.id) c on true
  left join lateral (select sum(case when movement_type = 'debt_decrease' then cash_amount else -cash_amount end) s
                       from customer_debts where invoice_id = i.id and source = 'allocation') al on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled' and i.payment_method in ('cash','bank','mixed')
    and abs(coalesce(c.s, 0) + coalesce(al.s, 0) - coalesce(i.amount_paid, 0)) > 0.01;

  return query
  select 'warning', 'invoice_debt_mismatch', 'المبلغ المتبقي على العميل غير مسجّل كدين',
         format('متبقي %s — مسجّل دين %s', i.total_amount - coalesce(i.amount_paid,0), coalesce(d.s, 0)), i.id, i.invoice_number
  from invoices i left join lateral (
      select sum(case when movement_type = 'debt_increase' then cash_amount else -cash_amount end) s
        from customer_debts where invoice_id = i.id) d on true
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled'
    and abs((i.total_amount - coalesce(i.amount_paid,0)) - coalesce(d.s, 0)) > 0.01;

  return query
  select 'error', 'cash_currency', 'حركة صندوق لفاتورة بعملة غلط',
         format('%s %s — عملة المحل %s', cm.amount, cm.currency, scur), cm.invoice_id, i.invoice_number
  from cash_movements cm join invoices i on i.id = cm.invoice_id
  where cm.store_id = sid and cm.currency is not null and upper(cm.currency) <> upper(coalesce(i.currency, scur));

  return query
  select 'error', 'piece_still_available', 'قطعة مباعة لكنها ما زالت تظهر متاحة',
         format('القطعة %s بالفاتورة %s', p.barcode, i.invoice_number), p.id, p.barcode
  from invoice_items ii join invoices i on i.id = ii.invoice_id join pieces p on p.id = ii.piece_id
  where i.store_id = sid and i.type = 'sale' and i.status <> 'cancelled' and p.status = 'available'
    and ii.line_total >= 0
    and not exists (  -- taken back later by a sales return or an exchange
      select 1 from invoice_items r join invoices ri on ri.id = r.invoice_id
       where r.piece_id = p.id and ri.status <> 'cancelled' and ri.created_at >= i.created_at and ri.id <> i.id
         and (ri.type = 'return' or r.line_total < 0 or r.returned_item_id = ii.id));

  return query
  select 'warning', 'daily_box_missing', 'دفعة فاتورة نقدية غير ظاهرة بالصندوق اليومي',
         format('%s %s %s بتاريخ %s', case cm.direction when 'in' then 'قبض' else 'صرف' end, cm.amount, coalesce(cm.currency, scur), to_char(cm.created_at, 'YYYY-MM-DD')),
         cm.invoice_id, i.invoice_number
  from cash_movements cm join invoices i on i.id = cm.invoice_id
  where cm.store_id = sid and cm.box = 'main' and cm.created_at >= '2026-08-08'
    and not exists (select 1 from daily_cash_log l where l.cash_movement_id = cm.id);

  return query
  select 'error', 'negative_stock', 'رصيد جملة سالب',
         format('عيار %s: %s غ', l.karat, l.weight_grams_remaining), l.id, l.karat || 'K'
  from gold_stock_lots l where l.store_id = sid and (l.weight_grams_remaining < 0 or coalesce(l.fabrication_pool_remaining, 0) < 0);
end $function$;
