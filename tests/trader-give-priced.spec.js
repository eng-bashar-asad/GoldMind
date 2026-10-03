// A piece handed to a trader at a fixed price: cash amount only on the trader, full cost kept.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('give a piece at a fixed price: no gold debt, price as cash, cost saved', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const calls = await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'تاجر أ' }],
    trader_movements: [],
    gold_prices: [{ store_id: STORE, karat: 24, price_per_gram: 400 }, { store_id: STORE, karat: 18, price_per_gram: 300 }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000123', status: 'available', karat: 18, weight_grams: 10, accounting_weight_grams: 10,
               cost_fabrication_per_gram: 20, accent_diamond_carat: 0.5, accent_diamond_price_per_carat: 1000 }],
  } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/ledger-ar.html?trader=t1&action=give');
  await page.waitForFunction(() => typeof setGiveStockMode === 'function' && currentTraderId === 't1');
  await page.evaluate(() => { if (document.getElementById('give-stock-form').classList.contains('hidden')) toggleGiveStockForm(); setGiveStockMode('barcode'); });
  await page.fill('#gs-barcode-input', '000123');
  await page.press('#gs-barcode-input', 'Enter');
  await expect(page.locator('#gs-cart-list > div')).toHaveCount(1);
  await page.check('input[name="gs-kind"][value="بسعر محدد"]');
  await expect(page.locator('#gs-preview-cost')).toContainText('3,700'); // 10×300 + 10×20 + 0.5×1000
  await page.fill('#gs-cart-list input[type=number]', '4500');
  await expect(page.locator('#gs-preview-price')).toContainText('4,500');
  await page.click('#gs-btn');
  await expect.poll(() => calls.some(c => c.method === 'POST' && c.name === 'trader_movements')).toBe(true);
  const [r] = JSON.parse(calls.find(c => c.method === 'POST' && c.name === 'trader_movements').body);
  expect([r.gold_24k_equivalent, r.fab_fee_amount, r.sale_cost, r.source, r.piece_id]).toEqual([0, 4500, 3700, 'stock_given', 'p1']);
  expect(errs).toEqual([]);
});
