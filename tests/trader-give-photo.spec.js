// Goods out to a trader by barcode: each piece shows its photo; tap = large in place, ✕ = small again.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('give stock: piece photo thumbnail opens large in its row and closes with ✕', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'تاجر أ' }],
    trader_movements: [],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000561', karat: 18, weight_grams: 7.69, description_ar: 'إسوارة', status: 'available', photo_url: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=' },
             { id: 'p2', store_id: STORE, barcode: '000552', karat: 18, weight_grams: 14.93, description_ar: 'عقد', status: 'available' }],
  } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/ledger-ar.html?trader=t1&action=give');
  await page.waitForFunction(() => typeof searchGiveStockBarcode === 'function' && currentTraderId === 't1');
  await page.evaluate(() => { if (document.getElementById('give-stock-form').classList.contains('hidden')) toggleGiveStockForm(); });
  for (const c of ['561', '552']) { await page.fill('#gs-barcode-input', c); await page.evaluate(() => searchGiveStockBarcode()); }
  await expect(page.locator('#gs-cart-list .gs-th img')).toHaveCount(1);       // the one without a photo shows an icon
  await page.click('#gs-cart-list .gs-th img');
  await expect(page.locator('#gs-cart-list .gs-big img')).toBeVisible();
  await page.click('#gs-cart-list .gs-big button');
  await expect(page.locator('#gs-cart-list .gs-big')).toHaveCount(0);
  expect(errs).toEqual([]);
});
