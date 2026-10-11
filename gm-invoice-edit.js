// Saving an edit of a posted invoice — shared by the invoice edit page and the
// sale screen (new-sale-ar.html?edit=<id>), so the money rules live in one place.
//
// s = {
//   invoice,            the invoices row as loaded
//   items,              lines after editing (existing ones keep .id, new ones have _new: true)
//   removedItems,       existing lines the user removed
//   method,             new payment method: cash | bank | credit | mixed
//   mixed: {cash, bank} paid now at the sale for "mixed" (shop currency, incl. other currencies)
//   newBreakdown,       pay_breakdown for mixed with other currencies (or null)
//   newCustomer,        {id} when the sale's customer changes
//   FX, FX_CUR, fxLineSum   sale priced in another currency (invoice page only)
//   counterparty        seller name (buyRetail)
// }
// Returns { error } on failure, {} when saved.

// Payments taken from the customer's account after the sale (later payments,
// deposits) that were allocated to this invoice. They stay paid whatever the edit.
// A mixed invoice also carries it as amount_paid − what was paid at the sale (older invoices have no allocation rows).
async function gmInvoiceLaterPaid(invoice) {
  if (invoice.type !== 'sale') return 0;
  const { data } = await goldmindClient.from('customer_debts').select('movement_type, cash_amount')
    .eq('invoice_id', invoice.id).eq('source', 'allocation');
  const r2 = v => Math.round(v * 100) / 100;
  const alloc = r2((data || []).reduce((t, r) => t + (r.movement_type === 'debt_decrease' ? 1 : -1) * Number(r.cash_amount || 0), 0));
  return Math.max(alloc, invoice.payment_method === 'mixed'
    ? r2(Number(invoice.amount_paid || 0) - Number(invoice.cash_paid_amount || 0) - Number(invoice.bank_paid_amount || 0)) : 0);
}
// same split of currencies? (jsonb hands keys back in its own order, so compare the values)
function gmSameBreakdown(a, b) {
  const norm = x => JSON.stringify((Array.isArray(x) && x.length ? x : []).map(r => [String(r.currency).toUpperCase(), Math.round(Number(r.amount) * 100), Number(r.rate), r.method]));
  return norm(a) === norm(b);
}

async function gmPostEditLedger(invoice, paymentMethod, amount, mode, description, editDelta) {
  const invoiceType = invoice.type;
  const isTraderInvoice = invoiceType === 'buyTrader' || invoiceType === 'buyRetail';
  const isAdding = mode === 'add';
  if (paymentMethod === 'cash' || paymentMethod === 'bank') {
    // Sale: adding money in means direction 'in'; purchase: adding means 'out'.
    const direction = invoiceType === 'sale' ? (isAdding ? 'in' : 'out') : (isAdding ? 'out' : 'in');
    await goldmindClient.from('cash_movements').insert({
      store_id: GOLDMIND_STORE_ID, box: 'main', direction, amount,
      description, created_by: GOLDMIND_STAFF_ID, invoice_id: invoice.id, edit_delta: !!editDelta
    });
  } else if (paymentMethod === 'credit' && invoiceType === 'sale') {
    await goldmindClient.from('customer_debts').insert({
      store_id: GOLDMIND_STORE_ID, customer_id: invoice.customer_id, invoice_id: invoice.id,
      movement_type: isAdding ? 'debt_increase' : 'debt_decrease',
      cash_amount: amount, gold_grams_24k: 0,
      notes: description, created_by: GOLDMIND_STAFF_ID
    });
  } else if (paymentMethod === 'credit' && isTraderInvoice) {
    await goldmindClient.from('trader_movements').insert({
      store_id: GOLDMIND_STORE_ID, trader_id: invoice.trader_id, invoice_id: invoice.id,
      movement_type: isAdding ? 'debt_increase' : 'debt_decrease',
      weight_grams: 0, karat: null, gold_24k_equivalent: 0, fab_fee_amount: amount,
      notes: description
    });
  }
}

async function gmSaveInvoiceEdit(s) {
  const invoice = s.invoice, items = s.items, removedItems = s.removedItems || [];
  const FX = s.FX || 0, FX_CUR = s.FX_CUR || '';
  const newPaymentMethod = s.method;
  const r2 = v => Math.round(v * 100) / 100;
  const newTotal = r2(items.reduce((t, it) => t + Number(it.line_total || 0), 0));
  const oldTotal = Number(invoice.total_amount);
  const later = await gmInvoiceLaterPaid(invoice);
  const mixCash = (s.mixed && s.mixed.cash) || 0, mixBank = (s.mixed && s.mixed.bank) || 0;

  if (invoice.type === 'sale') {
    if (later > newTotal + 0.009) return { error: 'دُفع على هذه الفاتورة لاحقاً ' + gmFormatNumber(later) + ' من حساب الزبون، وهو أكبر من الإجمالي الجديد. أعد الدفعة للزبون أولاً.' };
    if (newPaymentMethod === 'mixed' && mixCash + mixBank + later > newTotal + 0.009) return { error: 'المبلغ المدفوع (نقدي + فيزا) أكبر من إجمالي الفاتورة' };
  }

  // customer first (with the invoice's old amounts), so its remaining debt moves
  // to the new customer and any difference below is posted on the new one
  if (invoice.type === 'sale' && s.newCustomer && s.newCustomer.id && s.newCustomer.id !== invoice.customer_id) {
    const { error } = await goldmindClient.rpc('sale_invoice_change_customer', { p_invoice: invoice.id, p_customer: s.newCustomer.id });
    if (error) return { error: 'تعذّر تغيير الزبون: ' + error.message };
    invoice.customer_id = s.newCustomer.id;
  }

  const isTrader = invoice.type === 'buyTrader' || invoice.type === 'buyRetail';
  const updatePayload = {
    payment_method: newPaymentMethod,
    total_amount: newTotal,
    amount_paid: (newPaymentMethod === 'credit') ? 0 : newTotal
  };
  // Sale invoices: money already received stays received. Only a fully paid
  // invoice settles the difference in cash; otherwise the difference goes to
  // the customer's debt on this invoice (and a total below what was paid is refunded).
  let saleMoney = null;
  if (invoice.type === 'sale') {
    const oldPaid = Number(invoice.amount_paid || 0);
    const oldRem = oldTotal - oldPaid;
    const newPaid = newPaymentMethod === 'mixed' ? r2(mixCash + mixBank + later)
      : newPaymentMethod === 'credit' ? later : oldRem <= 0.009 ? newTotal : Math.max(later, Math.min(oldPaid, newTotal));
    saleMoney = { cashDelta: newPaid - oldPaid, debtDelta: (newTotal - newPaid) - oldRem };
    if (FX && newTotal > 0) {
      // keep the typed amounts exact: new rate = total typed ÷ invoice total
      const newRate = s.fxLineSum / newTotal;
      updatePayload.pay_fx_rate = newRate;
      saleMoney.fxDelta = r2(newPaid * newRate - oldPaid * FX);
    }
    updatePayload.amount_paid = newPaid;
    updatePayload.status = newTotal - newPaid > 0.009 ? 'unpaid' : 'paid';
    if (oldRem > 0.009 && newPaymentMethod !== 'credit' && newPaymentMethod !== 'mixed') updatePayload.payment_method = invoice.payment_method;
    updatePayload.cash_paid_amount = newPaymentMethod === 'mixed' ? mixCash : null;
    updatePayload.bank_paid_amount = newPaymentMethod === 'mixed' ? mixBank : null;
    // The currencies paid changed: take the invoice's old money out of the box (in the old
    // currencies) and put the new payment in (in the new ones), instead of one net delta.
    const newBD = s.newBreakdown || null;
    if (!FX && !gmSameBreakdown(invoice.pay_breakdown, newBD)) {
      updatePayload.pay_breakdown = newBD;
      saleMoney.replace = { newIn: Math.max(0, r2(newPaid - later)) };
    }
  } else if (invoice.type === 'buyRetail') {
    updatePayload.counterparty_name = s.counterparty || null;
  }

  // currency switch, step 1: before the invoice changes, so the box removes it in the OLD currencies
  if (saleMoney && saleMoney.replace) {
    const { data: cms } = await goldmindClient.from('cash_movements').select('direction, amount').eq('invoice_id', invoice.id);
    const inBox = r2((cms || []).reduce((t, m) => t + (m.direction === 'in' ? 1 : -1) * Number(m.amount || 0), 0));
    if (inBox > 0.009) {
      const { error } = await goldmindClient.from('cash_movements').insert({
        store_id: GOLDMIND_STORE_ID, box: 'main', direction: 'out', amount: inBox, invoice_id: invoice.id, created_by: GOLDMIND_STAFF_ID,
        description: 'تعديل عملات الدفع — إخراج المبلغ القديم للفاتورة ' + invoice.invoice_number
      });
      if (error) return { error: 'تعذّر حفظ الفاتورة: ' + error.message };
    }
  }
  const { error: invUpdateError } = await goldmindClient.from('invoices').update(updatePayload).eq('id', invoice.id);
  if (invUpdateError) return { error: 'تعذّر حفظ الفاتورة: ' + invUpdateError.message };

  // fields on lines that already existed
  for (const it of items.filter(i => !i._new)) {
    await goldmindClient.from('invoice_items').update({
      description: it.description, weight_grams: it.weight_grams, karat: it.karat, line_total: it.line_total
    }).eq('id', it.id);
  }

  // brand-new lines (a purchase gets a new piece in stock; a sale line reuses a
  // piece found by barcode, or stays unlinked like a manual sale line)
  for (const it of items.filter(i => i._new)) {
    let pieceId = it.piece_id;
    if (!pieceId && isTrader) {
      const { data: barcode, error: bcError } = await goldmindClient.rpc('next_piece_barcode', { target_store_id: GOLDMIND_STORE_ID, category: 'gold' });
      const { data: newPiece } = await goldmindClient.from('pieces').insert({
        store_id: GOLDMIND_STORE_ID, barcode: bcError ? null : barcode,
        weight_grams: it.weight_grams, karat: it.karat, description_ar: it.description,
        status: 'available', created_by: GOLDMIND_STAFF_ID
      }).select().single();
      pieceId = newPiece ? newPiece.id : null;
    } else if (pieceId && invoice.type === 'sale') {
      await goldmindClient.from('pieces').update({ status: 'sold' }).eq('id', pieceId);
      await goldmindClient.from('piece_movements').insert({ store_id: GOLDMIND_STORE_ID, piece_id: pieceId, event_type: 'sold', note: 'بيع بفاتورة ' + invoice.invoice_number + ' (أُضيفت عند تعديل الفاتورة)', created_by: GOLDMIND_STAFF_ID });
    }
    await goldmindClient.from('invoice_items').insert({
      invoice_id: invoice.id, piece_id: pieceId, barcode: it.barcode,
      karat: it.karat, weight_grams: it.weight_grams, accounting_weight_grams: it.accounting_weight_grams,
      fabrication_fee: 0, line_total: it.line_total,
      description: it.description, description_en: it.description_en,
      gold_price_per_gram: it.gold_price_per_gram
    });
  }

  // removed lines: pieces / diamonds / bulk-lot weight go back to stock
  const bulkRestoreByLot = {};
  for (const it of removedItems) {
    await goldmindClient.from('invoice_items').delete().eq('id', it.id);
    if (it.piece_id) {
      await goldmindClient.from('pieces').update({ status: invoice.type === 'sale' ? 'available' : 'cancelled' }).eq('id', it.piece_id);
      await goldmindClient.from('piece_movements').insert({ store_id: GOLDMIND_STORE_ID, piece_id: it.piece_id, event_type: invoice.type === 'sale' ? 'returned' : 'status_changed',
        note: 'حُذفت من الفاتورة ' + invoice.invoice_number + ' عند التعديل' + (invoice.type === 'sale' ? ' فعادت متوفرة' : ''), created_by: GOLDMIND_STAFF_ID });
    }
    if (it.diamond_piece_id) {
      await goldmindClient.from('diamond_pieces').update({ status: invoice.type === 'sale' ? 'available' : 'cancelled' }).eq('id', it.diamond_piece_id);
    }
    if (it.gold_stock_lot_id && it.weight_grams && invoice.type === 'sale') {
      bulkRestoreByLot[it.gold_stock_lot_id] = (bulkRestoreByLot[it.gold_stock_lot_id] || 0) + Number(it.weight_grams);
    }
  }
  for (const lotId of Object.keys(bulkRestoreByLot)) {
    const { data: lot } = await goldmindClient.from('gold_stock_lots').select('weight_grams_remaining').eq('id', lotId).maybeSingle();
    if (lot) await goldmindClient.from('gold_stock_lots').update({ weight_grams_remaining: Number(lot.weight_grams_remaining) + bulkRestoreByLot[lotId] }).eq('id', lotId);
  }

  // the money / debt effect, dated today
  if (saleMoney) {
    if (saleMoney.replace) {
      // step 2: the new payment, split into the daily box per currency by the new pay_breakdown
      if (saleMoney.replace.newIn > 0.009) await goldmindClient.from('cash_movements').insert({
        store_id: GOLDMIND_STORE_ID, box: 'main', direction: 'in', amount: saleMoney.replace.newIn, invoice_id: invoice.id, created_by: GOLDMIND_STAFF_ID,
        description: 'تعديل عملات الدفع — المبلغ الجديد للفاتورة ' + invoice.invoice_number
      });
    } else if (Math.abs(saleMoney.cashDelta) > 0.009) {
      await goldmindClient.from('cash_movements').insert({
        store_id: GOLDMIND_STORE_ID, box: 'main', direction: saleMoney.cashDelta > 0 ? 'in' : 'out', amount: r2(Math.abs(saleMoney.cashDelta)),
        description: (saleMoney.cashDelta > 0 ? 'تحصيل فرق تعديل فاتورة ' : 'رد فرق تعديل فاتورة ') + invoice.invoice_number,
        created_by: GOLDMIND_STAFF_ID, invoice_id: invoice.id, edit_delta: true, // changes the invoice's own row in the daily box
        ...(saleMoney.fxDelta ? { fx_amount: Math.abs(saleMoney.fxDelta), fx_currency: FX_CUR } : {})
      });
    }
    if (Math.abs(saleMoney.debtDelta) > 0.009 && invoice.customer_id) {
      await goldmindClient.from('customer_debts').insert({
        store_id: GOLDMIND_STORE_ID, customer_id: invoice.customer_id, invoice_id: invoice.id,
        movement_type: saleMoney.debtDelta > 0 ? 'debt_increase' : 'debt_decrease',
        cash_amount: r2(Math.abs(saleMoney.debtDelta)), gold_grams_24k: 0, source: 'invoice_edit',
        notes: 'تعديل فاتورة ' + invoice.invoice_number, created_by: GOLDMIND_STAFF_ID
      });
    }
  } else if (invoice.payment_method === newPaymentMethod) {
    // same way of paying: post only the difference, so the box shows the invoice once with its final value
    const delta = r2(newTotal - oldTotal);
    if (Math.abs(delta) > 0.009) {
      await gmPostEditLedger(invoice, newPaymentMethod, Math.abs(delta), delta > 0 ? 'add' : 'remove',
        (delta > 0 ? 'زيادة' : 'نقص') + ' قيمة فاتورة ' + invoice.invoice_number + ' بعد التعديل', true);
    }
  } else {
    // way of paying changed (e.g. cash → on the trader's account): undo it in the old place, post it in the new one
    if (oldTotal > 0) await gmPostEditLedger(invoice, invoice.payment_method, oldTotal, 'remove', 'حذف قيمة فاتورة ' + invoice.invoice_number + ' (قبل التعديل)');
    if (newTotal > 0) await gmPostEditLedger(invoice, newPaymentMethod, newTotal, 'add', 'إضافة قيمة فاتورة ' + invoice.invoice_number + ' (بعد التعديل)');
  }
  return {};
}

// After saving, go back to where the invoice was opened from (accounting check,
// daily box, invoice list…), skipping the invoice view; else the invoice view.
function gmAfterInvoiceEdit(id) {
  try {
    const stack = JSON.parse(sessionStorage.getItem('gm_nav_stack') || '[]');
    while (stack.length && /(invoice-(edit|print)-ar|new-sale-ar)\.html/.test(stack[stack.length - 1])) stack.pop();
    if (stack.length) {
      sessionStorage.setItem('gm_nav_stack', JSON.stringify(stack));
      sessionStorage.setItem('gm_nav_going_back', '1');
      window.location.replace(stack[stack.length - 1]);
      return;
    }
  } catch (e) { /* storage unavailable → the invoice view */ }
  window.location.replace('invoice-print-ar.html?id=' + id);
}
