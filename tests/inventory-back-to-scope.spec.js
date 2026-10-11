// Back from a piece returns to the list it was opened from (box → karat), not the top of the inventory.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('inventory: قطع ذهبية → عيار 18 → piece → back reopens the 18K list', async ({ page }) => {
  const piece = (id, bc, k) => ({ id, store_id: STORE, barcode: bc, karat: k, weight_grams: 5, status: 'available', box_name: 'قطع ذهبية', piece_type: 'خاتم', description_ar: 'خاتم' });
  await install(page, { generic: false, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [piece('p1', '000001', 18), piece('p2', '000002', 18), piece('p3', '000003', 21)],
    gold_stock_lots: [], gold_prices: []
  } });
  await page.goto('/index-ar.html');
  await page.goto('/inventory-list-ar.html');
  await page.click('[onclick*="enterBox"]');
  await page.click('[onclick="showKaratPieces(18)"]');
  await expect(page).toHaveURL(/k=18/);
  await expect(page.locator('#piece-list-title')).toContainText('عيار 18');
  await page.click('a[href*="piece-edit-ar.html?id=p1"]');
  await page.waitForURL(/piece-edit-ar\.html/);
  await page.waitForTimeout(500);
  await page.evaluate(() => gmSmartBack('inventory-list-ar.html'));
  await page.waitForURL(/inventory-list-ar\.html\?.*k=18/);
  await expect(page.locator('#piece-list-title')).toContainText('عيار 18');
  await expect(page.locator('#pieces-list a[href*="piece-edit"]')).toHaveCount(2);
});
