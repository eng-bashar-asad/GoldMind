// Give-out to a trader: labels read by the camera join the voucher at once, one after another;
// the same label held in front of the camera is added only once.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('camera scans add pieces one after another, no duplicates', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
    trader_movements: [],
    pieces: [
      { id: 'pc1', store_id: STORE, barcode: '000709', status: 'available', karat: 18, weight_grams: 10, accounting_weight_grams: 9, cost_fabrication_per_gram: 5 },
      { id: 'pc2', store_id: STORE, barcode: '000710', status: 'available', karat: 21, weight_grams: 4, accounting_weight_grams: 4, cost_fabrication_per_gram: 5 },
    ],
  } });
  await page.goto('/ledger-ar.html?trader=t1&action=give');
  await page.waitForFunction(() => typeof toggleGiveStockForm === 'function' && typeof currentTraderId !== 'undefined' && currentTraderId === 't1');
  await page.evaluate(() => { if (document.getElementById('give-stock-form').classList.contains('hidden')) toggleGiveStockForm(); });
  await expect(page.locator('button[aria-label="مسح بالكاميرا"]')).toHaveCount(1);
  await page.evaluate(async () => { await gsOnScan('000709'); await gsOnScan('000709'); await gsOnScan('000710'); });
  await expect(page.locator('#gs-cart-list')).toContainText('000709');
  await expect(page.locator('#gs-cart-list')).toContainText('000710');
  expect(await page.evaluate(() => giveStockCart.length)).toBe(2);
  await expect(page.locator('#gs-scan-msg')).toContainText('المجموع 2 قطعة');
  expect(errs).toEqual([]);
});
