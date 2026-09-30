const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('count detail on computer: start screen hidden', async ({ page }) => {
  const pieces = [], exp = [];
  for (let i = 1; i <= 6; i++) { const bc = String(i).padStart(6, '0'); pieces.push({ id: 'p' + i, store_id: STORE, barcode: bc, status: 'available', weight_grams: 3, karat: 18, piece_type: 'عقد' }); exp.push({ count_id: 'k1', piece_id: 'p' + i, piece_source: 'gold', barcode: bc, match_value: bc, karat: 18, weight_grams: 3 }); }
  await install(page, { realCdn: true, db: { stores: [{ id: STORE, name: 'x' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], pieces,
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'completed', method: 'camera', scope: ['gold'], started_at: '2026-09-27T09:00:00Z', expected_piece_count: 6 }], inventory_count_expected: exp, inventory_count_scans: [] } });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/inventory-count-ar.html');
  await expect(page.locator('#scope-wrap')).toBeVisible();
  await page.locator('#past-sessions-list button').first().click();
  await expect(page.locator('#sd-review')).toContainText('ناقصة فعلاً');
  await expect(page.locator('#scope-wrap')).toBeHidden();
});
