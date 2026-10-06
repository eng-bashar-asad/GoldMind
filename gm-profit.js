// GoldMind — one profit formula for every screen (profit report, invoice
// "عرض الربح", reports page, financial report). Before this file each page
// had its own copy and they had drifted apart (e.g. one ignored diamonds).
//
// Profit of one invoice line =
//   sale price − gold value − VAT − making cost − diamond cost
//   gold value  = accounting weight × gold price per gram saved at the moment of sale
//   making cost = accounting weight × making cost per gram (or the fee stored on the line
//                 for pooled bulk-gold lots)
//   diamond cost = full diamond piece (carat × price/carat) + small accent diamonds on a gold piece
// A return line (invoice type 'return') counts the other way round.

// invoice_items select that brings everything gmLineProfit needs
var GM_PROFIT_ITEM_SELECT = '*, piece:piece_id(cost_fabrication_per_gram, purchase_cost, accent_diamond_carat, accent_diamond_price_per_carat, box_name), lot:gold_stock_lot_id(cost_fabrication_per_gram), diamond:diamond_piece_id(diamond_carat, diamond_price_per_carat, has_gold, gold_cost_fabrication_per_gram, box_name)';

// it: invoice_items row (with piece/lot/diamond joined as above)
// isReturn: true for lines of a return invoice
// vatMultiplier: 1 + vat_rate/100
// livePriceMap: { karat: price } — only used for very old lines saved before the price snapshot existed
function gmLineProfit(it, isReturn, vatMultiplier, livePriceMap) {
  var sign = isReturn ? -1 : 1;
  var num = function (v) { var n = Number(v); return isFinite(n) ? n : 0; };
  var isEstimated = it.gold_price_per_gram == null;
  var goldPrice = isEstimated ? num((livePriceMap || {})[it.karat]) : num(it.gold_price_per_gram);
  var weight = num(it.accounting_weight_grams != null ? it.accounting_weight_grams : it.weight_grams);
  var revenue = sign * num(it.line_total);
  var goldValue = sign * weight * goldPrice;
  var vat = revenue - revenue / (vatMultiplier || 1);
  var perGram = (it.piece && it.piece.cost_fabrication_per_gram) || (it.lot && it.lot.cost_fabrication_per_gram) ||
    (it.diamond && it.diamond.has_gold && it.diamond.gold_cost_fabrication_per_gram) || 0;
  // pooled opening-stock lots keep a manually entered fee on the line itself
  var fabCost = (it.lot && it.fabrication_fee) ? sign * num(it.fabrication_fee) : sign * weight * num(perGram);
  var diamondCost = it.diamond ? sign * num(it.diamond.diamond_carat) * num(it.diamond.diamond_price_per_carat) : 0;
  var accentCost = it.piece ? sign * num(it.piece.accent_diamond_carat) * num(it.piece.accent_diamond_price_per_carat) : 0;
  // A piece bought for a cash price: its cost is that price (bought for X, sold for Y).
  if (it.piece && it.piece.purchase_cost != null) {
    goldValue = sign * num(it.piece.purchase_cost); fabCost = 0; accentCost = 0;
  }
  var profit = revenue - goldValue - vat - fabCost - diamondCost - accentCost;
  return {
    revenue: revenue, goldValue: goldValue, vat: vat, fabCost: fabCost,
    diamondCost: diamondCost + accentCost, profit: profit,
    weight: weight, grossWeight: num(it.weight_grams), goldPrice: goldPrice, isEstimated: isEstimated
  };
}

// ponytail: self-check — bought 5180, sold 6700, no VAT → profit 1520
console.assert(gmLineProfit({ line_total: 6700, weight_grams: 11.72, karat: 18, gold_price_per_gram: 300, piece: { purchase_cost: 5180, cost_fabrication_per_gram: 10 } }, false, 1, {}).profit === 1520, 'gmLineProfit purchase_cost');

// Profit of one piece given to a wholesale trader (trader_movements row, source 'stock_given',
// with piece:piece_id(cost_fabrication_per_gram, accounting_weight_grams, weight_grams) joined):
//   making profit = rate/g × weight billed to the trader − our making cost/g × piece accounting weight in stock
//   gold profit   = (weight billed − piece accounting weight) → 24k × 24k gram price on the voucher day
var GM_TRADER_GIVE_SELECT = '*, piece:piece_id(barcode, cost_fabrication_per_gram, accounting_weight_grams, weight_grams)';
function gmTraderGiveProfit(m, price24Now) {
  var num = function (v) { var n = Number(v); return isFinite(n) ? n : 0; };
  var k = num(m.karat), pc = m.piece || {};
  var billed = k && num(m.gold_24k_equivalent) ? num(m.gold_24k_equivalent) * 24 / k : num(m.accounting_weight_grams != null ? m.accounting_weight_grams : m.weight_grams);
  var pieceAcc = m.piece_acc_weight != null ? num(m.piece_acc_weight)
    : (pc.accounting_weight_grams != null ? num(pc.accounting_weight_grams) : (pc.weight_grams != null ? num(pc.weight_grams) : billed));
  var r = { billed: billed, pieceAcc: pieceAcc, gross: num(m.weight_grams), fee: 0, cost: 0, making: 0, diff: 0, diff24: 0, goldVal: 0, goldNow: 0, profit: 0, unknownCost: false };
  if (m.sale_cost != null) { // piece given at a fixed price: profit = price − its full cost
    r.fee = num(m.fab_fee_amount); r.cost = num(m.sale_cost); r.making = r.profit = r.fee - r.cost; return r;
  }
  var perGram = pc.cost_fabrication_per_gram != null ? pc.cost_fabrication_per_gram : m.cost_fab_per_gram;
  r.unknownCost = perGram == null;
  r.fee = billed * num(m.fab_fee_per_gram);
  r.cost = pieceAcc * num(perGram);
  r.making = r.fee - r.cost;
  r.diff = billed - pieceAcc; r.diff24 = r.diff * k / 24;
  r.goldVal = r.diff24 * (m.gold_price_24k != null ? num(m.gold_price_24k) : num(price24Now));
  r.goldNow = r.diff24 * num(price24Now);
  r.profit = r.making + r.goldVal;
  return r;
}
// ponytail: self-check — billed 10 g 18k, stock 9 g, 15/g vs our 6/g, 24k at 100 → 96 + 75
console.assert(gmTraderGiveProfit({ karat: 18, gold_24k_equivalent: 7.5, piece_acc_weight: 9, fab_fee_per_gram: 15, gold_price_24k: 100, piece: { cost_fabrication_per_gram: 6 } }, 120).profit === 171, 'gmTraderGiveProfit');

// ---------------------------------------------------------------------------
// Profit popups and per-customer / per-trader profit for a period.
// Used on the customer page (customer-debts-ar.html) and the trader page (ledger-ar.html).
// Needs goldmindClient / GOLDMIND_STORE_ID / GOLDMIND_STAFF_ID from supabase-config.js.
// ---------------------------------------------------------------------------
var gmProfitAllowed = null;
async function gmCanSeeProfit() {
  if (gmProfitAllowed !== null) return gmProfitAllowed;
  for (var i = 0; i < 100 && !(typeof GOLDMIND_STAFF_ID !== 'undefined' && GOLDMIND_STAFF_ID); i++) await new Promise(function (r) { setTimeout(r, 200); });
  try {
    var res = await goldmindClient.from('staff').select('role, permissions').eq('id', GOLDMIND_STAFF_ID).maybeSingle();
    var st = res.data;
    gmProfitAllowed = !!(st && (st.role === 'owner' || (st.permissions && st.permissions.view_profit_report === true)));
  } catch (e) { gmProfitAllowed = false; }
  if (gmProfitAllowed) {
    if (document.body) document.body.classList.add('gm-can-profit');
    else document.addEventListener('DOMContentLoaded', function () { document.body.classList.add('gm-can-profit'); });
  }
  return gmProfitAllowed;
}
(function () { // profit buttons/panels stay hidden for staff without the profit-report permission
  var css = document.createElement('style');
  css.textContent = '.gm-profit-btn{display:none!important}body.gm-can-profit .gm-profit-btn{display:flex!important}';
  document.head.appendChild(css);
  if (typeof goldmindClient !== 'undefined') gmCanSeeProfit();
})();

function gmPN(v, d) { return (Number(v) || 0).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d }); }
function gmPRow(label, value, cls) {
  var v = String(value), unit = / غ$/.test(v) ? ' غ' : '';
  if (unit) v = v.slice(0, -2); // keep the unit after the number in RTL
  return '<div class="flex justify-between gap-3 py-1.5 border-b border-outline-variant ' + (cls || '') + '"><span>' + label + '</span><span class="font-data-mono"><bdi dir="ltr">' + v + '</bdi>' + unit + '</span></div>';
}
function gmProfitPopup(title, sub, total, bodyHtml) {
  var m = document.getElementById('gm-profit-modal');
  if (!m) {
    m = document.createElement('div');
    m.id = 'gm-profit-modal';
    m.className = 'fixed inset-0 z-[80] bg-black/40 flex items-center justify-center p-3';
    m.addEventListener('click', function (e) { if (e.target === m) m.remove(); });
    document.body.appendChild(m);
  }
  m.innerHTML = '<div class="bg-white rounded-2xl w-full max-w-md max-h-[90vh] overflow-y-auto p-4 text-[13px]" id="gm-profit-body">' +
    '<div class="flex items-center justify-between mb-1"><b class="text-[16px]">' + title + '</b>' +
    '<button type="button" onclick="document.getElementById(\'gm-profit-modal\').remove()" class="p-1" aria-label="إغلاق"><span class="material-symbols-outlined">close</span></button></div>' +
    '<div class="text-[11px] text-on-surface-variant mb-3">' + (sub || '') + '</div>' +
    (total == null ? '' : '<div class="rounded-xl p-4 mb-3 text-center" style="background:' + (total >= 0 ? '#D7EBD2;color:#14532d' : '#FBEAEA;color:#7f1d1d') + '"><div class="text-[12px] font-bold">صافي الربح</div>' +
      '<div class="text-[26px] font-bold font-data-mono" id="gm-profit-total" dir="ltr">' + gmPN(total, 2) + '</div></div>') +
    bodyHtml + '</div>';
}

async function gmStoreProfitContext() {
  var r = await Promise.all([
    goldmindClient.from('stores').select('vat_rate').eq('id', GOLDMIND_STORE_ID).maybeSingle(),
    goldmindClient.from('gold_prices').select('karat, price_per_gram').eq('store_id', GOLDMIND_STORE_ID)
  ]);
  var prices = {};
  (r[1].data || []).forEach(function (p) { prices[p.karat] = Number(p.price_per_gram) || 0; });
  return { vatMul: 1 + (Number(r[0].data && r[0].data.vat_rate) || 0) / 100, prices: prices };
}

// profit of sale/return invoices (array of {id, type, ...}) → { total, revenue, weight, byInvoice }
async function gmInvoicesProfit(invoices) {
  var out = { total: 0, revenue: 0, weight: 0, byInvoice: {} };
  var ids = invoices.map(function (i) { return i.id; });
  if (!ids.length) return out;
  var ctx = await gmStoreProfitContext(), items = [];
  for (var s = 0; s < ids.length; s += 100) {
    var res = await goldmindClient.from('invoice_items').select(GM_PROFIT_ITEM_SELECT).in('invoice_id', ids.slice(s, s + 100));
    items = items.concat(res.data || []);
  }
  var typeOf = {}; invoices.forEach(function (i) { typeOf[i.id] = i.type; });
  items.forEach(function (it) {
    var p = gmLineProfit(it, typeOf[it.invoice_id] === 'return', ctx.vatMul, ctx.prices);
    out.total += p.profit; out.revenue += p.revenue - p.vat; out.weight += (typeOf[it.invoice_id] === 'return' ? -1 : 1) * p.grossWeight;
    out.byInvoice[it.invoice_id] = (out.byInvoice[it.invoice_id] || 0) + p.profit;
  });
  return out;
}

async function gmInvoiceProfitPopup(invoiceId, label) {
  gmProfitPopup('ربح الفاتورة', 'جارِ الحساب...', null, '');
  var res = await goldmindClient.from('invoices').select('id, type, invoice_number, created_at').eq('id', invoiceId).maybeSingle();
  var inv = res.data; if (!inv) return;
  var ctx = await gmStoreProfitContext();
  var r2 = await goldmindClient.from('invoice_items').select(GM_PROFIT_ITEM_SELECT).eq('invoice_id', invoiceId);
  var t = { revenue: 0, vat: 0, goldValue: 0, fabCost: 0, diamondCost: 0, profit: 0 };
  var rows = (r2.data || []).map(function (it) {
    var p = gmLineProfit(it, inv.type === 'return', ctx.vatMul, ctx.prices);
    Object.keys(t).forEach(function (k) { t[k] += p[k]; });
    return gmPRow(String(it.barcode || it.description || 'قطعة').replace(/[<>&"]/g, ''), gmPN(p.profit, 2));
  });
  gmProfitPopup('ربح الفاتورة', (inv.invoice_number || '') + ' · ' + rows.length + ' قطعة', t.profit,
    gmPRow('المبيع بدون ضريبة', gmPN(t.revenue - t.vat, 2)) + gmPRow('قيمة الذهب', gmPN(t.goldValue, 2)) +
    gmPRow('كلفة المصنعية', gmPN(t.fabCost, 2)) + (t.diamondCost ? gmPRow('كلفة الألماس', gmPN(t.diamondCost, 2)) : '') +
    '<div class="font-bold mt-3 mb-1">ربح كل قطعة</div>' + rows.join(''));
}

// sum of give-out vouchers' profit; rows = trader_movements with GM_TRADER_GIVE_SELECT
function gmSumTraderGive(rows, price24Now) {
  var t = { n: rows.length, billed: 0, pieceAcc: 0, fee: 0, cost: 0, making: 0, diff: 0, diff24: 0, goldVal: 0, goldNow: 0, profit: 0, unknown: 0 };
  rows.forEach(function (m) {
    var r = gmTraderGiveProfit(m, price24Now); if (r.unknownCost) t.unknown++;
    ['billed', 'pieceAcc', 'fee', 'cost', 'making', 'diff', 'diff24', 'goldVal', 'goldNow', 'profit'].forEach(function (k) { t[k] += r[k] || 0; });
  });
  return t;
}
function gmTraderGiveHtml(t) {
  return gmPRow('الوزن المحسوب على التاجر', gmPN(t.billed, 3) + ' غ') + gmPRow('الوزن المحاسبي للقطع بالمخزن', gmPN(t.pieceAcc, 3) + ' غ') +
    '<div class="font-bold mt-3 mb-1">المصنعية</div>' +
    gmPRow('مصنعية التاجر', gmPN(t.fee, 2)) + gmPRow('كلفة مصنعيتنا', gmPN(t.cost, 2)) + gmPRow('ربح المصنعية', gmPN(t.making, 2), 'font-bold') +
    '<div class="font-bold mt-3 mb-1">فرق الذهب</div>' +
    gmPRow('فرق الوزن (بعيار القطع)', gmPN(t.diff, 3) + ' غ') + gmPRow('فرق الوزن عيار ٢٤', gmPN(t.diff24, 3) + ' غ') +
    gmPRow('قيمته يوم السند', gmPN(t.goldVal, 2), 'font-bold') + gmPRow('قيمته الآن', gmPN(t.goldNow, 2), 'text-on-surface-variant') +
    (t.unknown ? '<p class="text-[11px] text-error mt-2">' + t.unknown + ' قطعة بدون كلفة مصنعية مسجّلة، فحُسبت مصنعيتها كاملة ربحاً.</p>' : '') +
    '<p class="text-[11px] text-on-surface-variant mt-3">الربح = ربح المصنعية + قيمة فرق الذهب يوم السند.</p>';
}
async function gmPrice24() {
  var r = await goldmindClient.from('gold_prices').select('price_per_gram').eq('store_id', GOLDMIND_STORE_ID).eq('karat', 24).maybeSingle();
  return Number(r.data && r.data.price_per_gram) || 0;
}
async function gmVoucherProfitPopup(col, val) {
  gmProfitPopup('ربح السند', 'جارِ الحساب...', null, '');
  var r = await Promise.all([goldmindClient.from('trader_movements').select(GM_TRADER_GIVE_SELECT).eq(col, val).eq('source', 'stock_given'), gmPrice24()]);
  var rows = r[0].data || [];
  if (!rows.length) { gmProfitPopup('ربح السند', 'تعذّر حساب الربح', null, ''); return; }
  var t = gmSumTraderGive(rows, r[1]);
  gmProfitPopup('ربح السند', gmFormatDateTime(rows[0].created_at, { day: 'numeric', month: 'short', year: 'numeric' }) + ' · ' + rows.length + ' قطعة', t.profit, gmTraderGiveHtml(t));
}

// "أرباحي مع هذا الزبون / التاجر" for a period. kind: 'customer' | 'trader'
async function gmPartyProfitPopup(kind, partyId, name) {
  var today = new Date().toISOString().slice(0, 10);
  gmProfitPopup(kind === 'trader' ? 'أرباحي مع التاجر' : 'أرباحي مع الزبون', name ? String(name).replace(/[<>&"]/g, '') : '', null,
    '<div class="grid grid-cols-2 gap-2 mb-2">' +
    '<label class="text-[11px]">من تاريخ<input id="gm-pp-from" type="date" dir="ltr" class="w-full h-10 border border-outline-variant rounded-lg px-2 text-[13px]"/></label>' +
    '<label class="text-[11px]">إلى تاريخ<input id="gm-pp-to" type="date" dir="ltr" value="' + today + '" class="w-full h-10 border border-outline-variant rounded-lg px-2 text-[13px]"/></label></div>' +
    '<p class="text-[11px] text-on-surface-variant mb-2">اترك "من تاريخ" فارغاً لكل الفترة.</p>' +
    '<button type="button" id="gm-pp-go" class="w-full h-11 rounded-lg font-bold text-white mb-3" style="background:#3F6B47">عرض الأرباح</button>' +
    '<div id="gm-pp-out"></div>');
  document.getElementById('gm-pp-go').onclick = function () { gmPartyProfitRun(kind, partyId); };
  gmPartyProfitRun(kind, partyId);
}
async function gmPartyProfitRun(kind, partyId) {
  var out = document.getElementById('gm-pp-out'); if (!out) return;
  out.innerHTML = '<p class="text-center py-4">جارِ الحساب...</p>';
  var from = document.getElementById('gm-pp-from').value, to = document.getElementById('gm-pp-to').value;
  var range = function (q) {
    if (from) q = q.gte('created_at', gmDayStart(from));
    if (to) q = q.lt('created_at', gmDayStart(to, 1));
    return q;
  };
  var total, html;
  if (kind === 'trader') {
    var r = await Promise.all([range(goldmindClient.from('trader_movements').select(GM_TRADER_GIVE_SELECT).eq('trader_id', partyId).eq('source', 'stock_given')), gmPrice24()]);
    var rows = r[0].data || [];
    var vouchers = new Set(rows.map(function (m) { return m.batch_id || m.id; }));
    var t = gmSumTraderGive(rows, r[1]);
    total = t.profit;
    html = gmPRow('عدد السندات', vouchers.size) + gmPRow('عدد القطع', rows.length) + gmTraderGiveHtml(t);
  } else {
    var ri = await Promise.all([
      range(goldmindClient.from('invoices').select('id, type').eq('store_id', GOLDMIND_STORE_ID).eq('customer_id', partyId).in('type', ['sale', 'return']).neq('status', 'cancelled')),
      range(goldmindClient.from('customer_debts').select('cash_amount').eq('store_id', GOLDMIND_STORE_ID).eq('customer_id', partyId).eq('source', 'discount'))
    ]);
    var invs = ri[0].data || [];
    var p = await gmInvoicesProfit(invs);
    var disc = (ri[1].data || []).reduce(function (a, d) { return a + (Number(d.cash_amount) || 0); }, 0);
    total = p.total - disc;
    html = gmPRow('عدد الفواتير', invs.filter(function (i) { return i.type === 'sale'; }).length + (invs.some(function (i) { return i.type === 'return'; }) ? ' (+ ' + invs.filter(function (i) { return i.type === 'return'; }).length + ' مرتجع)' : '')) +
      gmPRow('الوزن المباع (قائم)', gmPN(p.weight, 3) + ' غ') + gmPRow('المبيعات بدون ضريبة', gmPN(p.revenue, 2)) +
      gmPRow('ربح الفواتير', gmPN(p.total, 2), 'font-bold') + (disc ? gmPRow('خصومات على الدين', '− ' + gmPN(disc, 2), 'text-error') : '');
  }
  out.innerHTML = '<div class="rounded-xl p-4 mb-3 text-center" style="background:' + (total >= 0 ? '#D7EBD2;color:#14532d' : '#FBEAEA;color:#7f1d1d') + '"><div class="text-[12px] font-bold">صافي الربح بالفترة</div>' +
    '<div class="text-[26px] font-bold font-data-mono" id="gm-pp-total" dir="ltr">' + gmPN(total, 2) + '</div></div>' + html;
}
// local-day start as an ISO instant (dayOffset 1 = next day)
function gmDayStart(ymd, dayOffset) { var d = new Date(ymd + 'T00:00:00'); if (dayOffset) d.setDate(d.getDate() + dayOffset); return d.toISOString(); }
