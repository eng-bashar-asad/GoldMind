// The running count never gets lost: leaving the scan screen goes back to the list,
// with the running count on top and in the history (Bashar 2026-11-01).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('back from scanning keeps the running count on top of the list', async ({ page }) => {
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  page.on('dialog', d => d.accept());
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, status: 'available', barcode: 'A1' }, { id: 'p2', store_id: STORE, status: 'available', barcode: 'A2' }],
    inventory_counts: [
      { id: 'k1', store_id: STORE, status: 'in_progress', method: 'camera', scope: ['gold'], started_at: '2026-11-01T08:00:00Z', expected_piece_count: 2 },
      { id: 'k0', store_id: STORE, status: 'posted', method: 'camera', scope: ['gold'], started_at: '2026-10-01T08:00:00Z', expected_piece_count: 2, matched_count: 2 },
    ],
    inventory_count_expected: [
      { count_id: 'k1', piece_id: 'p1', piece_source: 'gold', barcode: 'A1', match_value: 'A1' },
      { count_id: 'k1', piece_id: 'p2', piece_source: 'gold', barcode: 'A2', match_value: 'A2' },
    ],
    inventory_count_scans: [{ id: 's1', count_id: 'k1', store_id: STORE, rfid_epc: 'A1', match_status: 'matched', scanned_by: STAFF, scanned_at: '2026-11-01T08:01:00Z' }],
  } });
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); }; });
  await page.goto('/inventory-count-ar.html');
  await expect(page.locator('#resume-banner')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#running-matched')).toHaveText('1');
  await expect(page.locator('#new-count-btn')).toBeDisabled();
  await expect(page.locator('#past-sessions-list')).toContainText('جارٍ');

  await page.click('text=متابعة المسح');
  await expect(page.locator('#scan-wrap')).not.toHaveClass(/\bhidden\b/);
  await page.click('#scan-wrap >> text=قائمة الجرد');
  await expect(page.locator('#scan-wrap')).toHaveClass(/\bhidden\b/);
  await expect(page.locator('#hub-wrap')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#resume-banner')).not.toHaveClass(/\bhidden\b/);

  // the running row in the history opens the scan screen again
  await page.locator('#past-sessions-list button', { hasText: 'جارٍ' }).click();
  await expect(page.locator('#scan-wrap')).not.toHaveClass(/\bhidden\b/);
  expect(errors).toEqual([]);
});
