// Before posting a count, staff can add a missing piece they found and delete a wrong/extra scan,
// until nothing is missing or extra.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('count report: add found piece, remove extra scan, reach a balanced count', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const errors = []; page.on('pageerror', e => errors.push(e.message + ' @ ' + e.stack.split('\n').slice(1,3).join('|')));
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [
      { id: 'p1', store_id: STORE, status: 'available', barcode: 'A1', karat: 18, weight_grams: 5 },
      { id: 'p2', store_id: STORE, status: 'available', barcode: 'A2', karat: 21, weight_grams: 7 },
    ],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'in_progress', method: 'camera', scope: ['gold'], started_at: '2026-09-28T10:00:00Z', expected_piece_count: 2 }],
    inventory_count_expected: [
      { count_id: 'k1', piece_id: 'p1', piece_source: 'gold', barcode: 'A1', match_value: 'A1', karat: 18, weight_grams: 5 },
      { count_id: 'k1', piece_id: 'p2', piece_source: 'gold', barcode: 'A2', match_value: 'A2', karat: 21, weight_grams: 7 },
    ],
    inventory_count_scans: [
      { id: 's1', count_id: 'k1', store_id: STORE, rfid_epc: 'A1', match_status: 'matched', scanned_by: STAFF, scanned_at: '2026-09-28T10:01:00Z' },
      { id: 's2', count_id: 'k1', store_id: STORE, rfid_epc: 'ZZ9', match_status: 'unexpected', scanned_by: STAFF, scanned_at: '2026-09-28T10:02:00Z' },
    ],
  } });
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); }; });
  await page.goto('/inventory-count-ar.html');
  await page.waitForFunction(() => typeof inProgressSession !== 'undefined' && inProgressSession);
  await page.click('text=استئناف الجلسة');
  await expect(page.locator('#stat-matched')).toHaveText('1');
  await page.click('#finish-btn');
  await expect(page.locator('#report-missing-count')).toHaveText('1');
  await expect(page.locator('#report-surplus-count')).toHaveText('1');
  await expect(page.locator('#report-balanced')).toHaveClass(/\bhidden\b/);

  await page.click(`button[onclick="openSubScreen('missing')"]`);
  await page.click('text=وُجدت — أضفها');
  await expect(page.locator('#subscreen-list')).toContainText('لا توجد قطع ناقصة');
  const add = calls.find(c => c.method === 'POST' && c.name === 'inventory_count_scans');
  expect(JSON.parse(add.body)).toMatchObject({ count_id: 'k1', rfid_epc: 'A2', match_status: 'matched', scan_method: 'manual' });

  await page.click('#subscreen-wrap >> text=رجوع للجرد');
  await page.click(`button[onclick="openSubScreen('surplus')"]`);
  await page.click('#subscreen-list >> text=احذفها');
  await expect(page.locator('#subscreen-list')).toContainText('لا توجد مسوحات زيادة');
  expect(calls.some(c => c.method === 'DELETE' && c.name === 'inventory_count_scans' && c.url.includes('rfid_epc=eq.ZZ9'))).toBe(true);

  await page.click('#subscreen-wrap >> text=رجوع للجرد');
  await expect(page.locator('#report-missing-count')).toHaveText('0');
  await expect(page.locator('#report-surplus-count')).toHaveText('0');
  await expect(page.locator('#report-balanced')).not.toHaveClass(/\bhidden\b/);
  expect(errors).toEqual([]);
});
