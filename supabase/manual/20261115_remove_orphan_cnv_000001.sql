-- يحذف ما تبقّى من سند تسكير العملات CNV-000001 للتاجر مهند كليل (الجزء النقدي 31,691.03 USD)
-- بعد هذا يرجع رصيده النقدي كما كان قبل التسكير. جزء الذهب محذوف من قبل.
delete from public.trader_movements
 where id = '93c41007-5a93-4cb0-bfa3-24fa1b694055'
   and source = 'gold_to_cash'
   and voucher_no = 'CNV-000001';
