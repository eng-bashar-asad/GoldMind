// Searching an old (replaced) barcode still finds the piece by its current barcode.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('sale search with an old sticker finds the piece and warns it is cancelled', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: 'NEW1', status: 'available', weight_grams: 10, karat: 18, description_ar: 'خاتم' }],
    piece_barcode_history: [{ store_id: STORE, old_barcode: 'OLD9', new_barcode: 'NEW1', piece_id: 'p1' }],
  } });
  await page.goto('/new-sale-ar.html');
  await page.waitForFunction(() => typeof searchByBarcode === 'function');
  await page.fill('#barcode-search-input', 'OLD9');
  await page.evaluate(() => searchByBarcode());
  await expect(page.locator('#barcode-result')).toContainText('ملغى');
  await expect(page.locator('#barcode-result')).toContainText('NEW1');
});
