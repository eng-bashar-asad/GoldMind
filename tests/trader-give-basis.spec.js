// Give-out on the standing-weight basis: the choice sticks, billing uses the standing weight, an edited standing weight is used.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('standing-weight basis stays selected and bills on the standing weight', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
    trader_movements: [],
    pieces: [{ id: 'pc1', store_id: STORE, barcode: '000709', status: 'available', karat: 18, weight_grams: 10, accounting_weight_grams: 9, cost_fabrication_per_gram: 5 }],
  } });
  await page.goto('/ledger-ar.html?trader=t1&action=give');
  await page.waitForFunction(() => typeof toggleGiveStockForm === 'function' && typeof currentTraderId !== 'undefined' && currentTraderId === 't1');
  await page.evaluate(() => { if (document.getElementById('give-stock-form').classList.contains('hidden')) toggleGiveStockForm(); });
  await page.locator('#gs-basis button[data-v=gross]').click();
  // close and reopen: the choice must stick
  await page.evaluate(() => toggleGiveStockForm());
  await page.evaluate(() => toggleGiveStockForm());
  await expect(page.locator('#gs-basis button[data-v=gross]')).toHaveAttribute('style', /background/);
  // scan the piece: billed on standing weight 10 (not accounting 9)
  await page.locator('#gs-barcode-input').fill('000709');
  await page.evaluate(() => searchGiveStockBarcode());
  await expect(page.locator('#gs-cart-list')).toContainText('000709');
  await expect.poll(async () => parseFloat(await page.locator('#gs-preview-gold').innerText())).toBeCloseTo(10 * 18 / 24, 2);
  // editing the standing weight changes the billing
  await page.locator('#gs-cart-list input').first().fill('8');
  await expect.poll(async () => parseFloat(await page.locator('#gs-preview-gold').innerText())).toBeCloseTo(8 * 18 / 24, 2);
});
