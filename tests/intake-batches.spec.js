// بشار 2026-11-23: intake voucher pieces — status in Arabic («مباعة» not «sold»), 3 per row on the computer
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('intake voucher: statuses in Arabic and a 3-column grid', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  const T = '2026-11-23T12:03:00Z';
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    piece_intake_batches: [{ id: 'b1', store_id: STORE, created_at: T, piece_count: 2, total_weight: 10 }],
    pieces: [{ id: 'p1', store_id: STORE, intake_batch_id: 'b1', barcode: '001313', piece_type: 'عقد', weight_grams: 5, status: 'sold', created_at: T },
             { id: 'p2', store_id: STORE, intake_batch_id: 'b1', barcode: '001314', piece_type: 'خاتم', weight_grams: 5, status: 'available', created_at: T }] } });
  await page.goto('/intake-batches-ar.html');
  await page.evaluate(() => openBatch('b1'));
  await expect(page.locator('#batch-pieces')).toContainText('مباعة');
  await expect(page.locator('#batch-pieces')).toContainText('متوفرة');
  await expect(page.locator('#batch-pieces')).not.toContainText('sold');
  await expect(page.locator('#batch-pieces')).toHaveClass(/lg:grid-cols-3/);
});
