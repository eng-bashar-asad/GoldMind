// "إغلاق الجرد" re-reads the stock: a piece sold or deleted after the count started is not missing
// (Bashar 2026-11-01). Only p2, still available and not scanned, stays missing.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('closing a reopened count counts missing against the current stock', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [
      { id: 'p1', store_id: STORE, status: 'available', barcode: 'A1', karat: 18, weight_grams: 5 },
      { id: 'p2', store_id: STORE, status: 'available', barcode: 'A2', karat: 18, weight_grams: 6 },
      { id: 'p3', store_id: STORE, status: 'sold', barcode: 'A3', karat: 18, weight_grams: 7 },
      // p4 was deleted after the count started: no row any more
    ],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'in_progress', method: 'camera', scope: ['gold'], started_at: '2026-11-01T08:00:00Z', expected_piece_count: 4 }],
    inventory_count_expected: ['1', '2', '3', '4'].map(n => (
      { count_id: 'k1', piece_id: 'p' + n, piece_source: 'gold', barcode: 'A' + n, match_value: 'A' + n, karat: 18, weight_grams: 5 })),
    inventory_count_scans: [
      { id: 's1', count_id: 'k1', store_id: STORE, rfid_epc: 'A1', match_status: 'matched', scanned_by: STAFF, scanned_at: '2026-11-01T08:01:00Z' },
    ],
  } });
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); }; });
  await page.goto('/inventory-count-ar.html');
  await page.waitForFunction(() => typeof inProgressSession !== 'undefined' && inProgressSession);
  await page.click('text=متابعة المسح');
  await expect(page.locator('#stat-expected')).toHaveText('2');
  await expect(page.locator('#finish-btn')).toHaveText('إغلاق الجرد');
  await page.click('#finish-btn');
  await expect(page.locator('#report-expected')).toHaveText('2');
  await expect(page.locator('#report-missing-count')).toHaveText('1');
  expect(await page.evaluate(() => missingListCache.map(p => p.barcode))).toEqual(['A2']);
  expect(errors).toEqual([]);
});
