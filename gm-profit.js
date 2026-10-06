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
