// A hanging connection must not leave "finish" stuck on "جارِ الإنهاء..." forever.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('finish: slow network gives a message and the button comes back', async ({ page }) => {
  test.setTimeout(90000);
  const dialogs = [];
  page.on('dialog', d => { dialogs.push(d.message()); d.accept(); });
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, status: 'available', barcode: 'A1', karat: 18, weight_grams: 5 }],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'in_progress', method: 'camera', scope: ['gold'], started_at: '2026-09-28T10:00:00Z', expected_piece_count: 1 }],
    inventory_count_expected: [{ count_id: 'k1', piece_id: 'p1', piece_source: 'gold', barcode: 'A1', match_value: 'A1', karat: 18, weight_grams: 5 }],
    inventory_count_scans: [],
  } });
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); }; });
  await page.goto('/inventory-count-ar.html');
  await page.waitForFunction(() => typeof inProgressSession !== 'undefined' && inProgressSession);
  await page.click('text=استئناف الجلسة');
  await page.waitForFunction(() => currentCountId === 'k1' && stats.expected === 1);
  // from now on the scans request never answers
  await page.route(/inventory_count_scans/, () => {});
  await page.click('#finish-btn');
  await expect(page.locator('#finish-btn')).toContainText('جارِ');
  await expect(page.locator('#finish-btn')).toHaveText('إنهاء الجلسة وعرض التقرير', { timeout: 40000 });
  expect(dialogs.some(m => m.includes('الاتصال بطيء'))).toBe(true);
});

test('finish works when the camera is not running (stop() throws)', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, status: 'available', barcode: 'A1', karat: 18, weight_grams: 5 }],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'in_progress', method: 'camera', scope: ['gold'], started_at: '2026-09-28T10:00:00Z', expected_piece_count: 1 }],
    inventory_count_expected: [{ count_id: 'k1', piece_id: 'p1', piece_source: 'gold', barcode: 'A1', match_value: 'A1', karat: 18, weight_grams: 5 }],
    inventory_count_scans: [],
  } });
  // html5-qrcode throws synchronously when asked to stop a camera that is not scanning
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.reject(new Error('NotAllowedError')); this.stop = () => { throw 'Cannot stop, scanner is not running or paused.'; }; this.clear = () => {}; }; });
  await page.goto('/inventory-count-ar.html');
  await page.waitForFunction(() => typeof inProgressSession !== 'undefined' && inProgressSession);
  await page.click('text=استئناف الجلسة');
  await page.waitForFunction(() => currentCountId === 'k1' && stats.expected === 1);
  await page.click('#finish-btn');
  await expect(page.locator('#report-wrap')).not.toHaveClass(/\bhidden\b/);
  expect(errs).toEqual([]);
});
