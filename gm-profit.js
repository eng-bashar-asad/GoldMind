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
var GM_PROFIT_ITEM_SELECT = '*, piece:piece_id(cost_fabrication_per_gram, accent_diamond_carat, accent_diamond_price_per_carat, box_name), lot:gold_stock_lot_id(cost_fabrication_per_gram), diamond:diamond_piece_id(diamond_carat, diamond_price_per_carat, has_gold, gold_cost_fabrication_per_gram, box_name)';

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
  var profit = revenue - goldValue - vat - fabCost - diamondCost - accentCost;
  return {
    revenue: revenue, goldValue: goldValue, vat: vat, fabCost: fabCost,
    diamondCost: diamondCost + accentCost, profit: profit,
    weight: weight, grossWeight: num(it.weight_grams), goldPrice: goldPrice, isEstimated: isEstimated
  };
}
