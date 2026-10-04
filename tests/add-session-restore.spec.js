// Add-piece page: the session list (and its intake voucher) survives editing a piece and coming back.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('add pieces: session list restored after visiting a piece', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000001', weight_grams: 5, accounting_weight_grams: 5, karat: 18, status: 'available', box_name: 'قطع ذهبية' },
             { id: 'p2', store_id: STORE, barcode: '000002', weight_grams: 7, accounting_weight_grams: 7, karat: 18, status: 'available', box_name: 'قطع ذهبية' }],
    piece_classification_options: [], diamond_pieces: [], zebra_label_fields: []
  } });
  await page.addInitScript(store => sessionStorage.setItem('gm-add-session', JSON.stringify({ store, batch: 'b1', ids: ['p2', 'p1'], at: Date.now() })), STORE);
  await page.goto('/inventory-add.html');
  await expect(page.locator('#session-list-count')).toHaveText('2');
  await expect(page.locator('#session-total-weight')).toContainText('12');
  expect(await page.evaluate(() => currentBatchId)).toBe('b1');
  expect(errs).toEqual([]);
});
