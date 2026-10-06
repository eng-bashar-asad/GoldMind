// Wholesale profit when a trader is billed on a heavier weight than the piece's
// accounting weight in stock: making profit + value of the gold difference.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-09-15T10:00:00Z';
const db = {
  stores: [{ id: STORE, name: 'محل', vat_rate: 0 }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  gold_prices: [{ store_id: STORE, karat: 24, price_per_gram: 120 }],
  pieces: [], diamond_pieces: [], invoices: [], invoice_items: [],
  // billed 10 g (18k → 7.5 g 24k) on gross; piece is 9 g accounting in stock, our making 6/g
  trader_movements: [{ id: 'm1', store_id: STORE, source: 'stock_given', batch_id: 'b1', weight_grams: 10, accounting_weight_grams: 10, piece_acc_weight: 9,
    gold_price_24k: 100, karat: 18, gold_24k_equivalent: 7.5, fab_fee_per_gram: 15, fab_fee_amount: 150, created_at: T,
    trader: { name: 'جليل' }, piece: { barcode: '000001', cost_fabrication_per_gram: 6, accounting_weight_grams: 9, weight_grams: 10 } }],
};

test('voucher profit = making on billed weight − our cost on stock weight + gold difference value', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db });
  await page.goto('/profit-report-ar.html');
  await page.fill('#date-from', '2026-09-01');
  await page.fill('#date-to', '2026-09-30');
  await page.click('#apply-filters-btn');
  const br = page.locator('#pr-brief');
  // making: 15×10 − 6×9 = 96 ; gold: (10−9)×18/24 = 0.75 g 24k × 100 = 75
  await expect(br.locator('tr', { hasText: 'مصنعية التجار' })).toContainText('96.00');
  await expect(br.locator('tr', { hasText: 'فرق وزن الذهب' })).toContainText('75.00');
  await expect(br.locator('tr', { hasText: 'فرق وزن الذهب' })).toContainText('0.750');
  await expect(br.locator('tr', { hasText: 'صافي ربح المحل' })).toContainText('171.00');
  await page.click('.pr-view[data-view="full"]');
  const v = page.locator('#pr-sections tr', { hasText: 'جليل' }).first();
  for (const t of ['9.000', '10.000', '150.00', '54.00', '96.00', '1.000', '0.750', '75.00', '90.00', '171.00']) await expect(v).toContainText(t);
  expect(errs).toEqual([]);
});
