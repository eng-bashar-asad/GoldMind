// Regenerating a piece's barcode: confirm first, the old number is cancelled in counts.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('regenerate asks for confirmation, then shows the new barcode', async ({ page }) => {
  let asked = '';
  page.on('dialog', d => { asked = d.message(); d.accept(); });
  const calls = await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000100', status: 'available', weight_grams: 10, karat: 18 }],
  }, rpc: { regenerate_piece_barcode: () => ({ body: '000777' }) } });
  await page.goto('/piece-edit-ar.html?id=p1');
  await page.locator('#gmEditBox summary').click();
  await page.click('#regen-barcode-btn');
  await expect(page.locator('#barcode-id')).toHaveValue('000777');
  expect(asked).toContain('000100');
  const rpc = calls.find(c => c.kind === 'rest/v1/rpc' && c.name === 'regenerate_piece_barcode');
  expect(JSON.parse(rpc.body)).toEqual({ p_piece_id: 'p1' });
});

test('a cancelled old barcode is listed, never counted as a match', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, status: 'available', barcode: 'A1', karat: 18, weight_grams: 5 }],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'in_progress', method: 'camera', scope: ['gold'], started_at: '2026-10-13T10:00:00Z', expected_piece_count: 1 }],
    inventory_count_expected: [{ count_id: 'k1', piece_id: 'p1', piece_source: 'gold', barcode: 'A1', match_value: 'A1', karat: 18, weight_grams: 5 }],
    inventory_count_scans: [],
    piece_barcode_history: [{ store_id: STORE, old_barcode: 'OLD9', piece_id: 'p2', pieces: { description_ar: 'خاتم' } }],
  } });
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); }; });
  await page.goto('/inventory-count-ar.html');
  await page.waitForFunction(() => typeof inProgressSession !== 'undefined' && inProgressSession);
  await page.click('text=استئناف الجلسة');
  await expect(page.locator('#scan-wrap')).not.toHaveClass(/\bhidden\b/);
  await page.evaluate(() => handleScan('OLD9', 'camera'));
  await expect(page.locator('#cancelled-count')).toHaveText('1');
  await expect(page.locator('#cancelled-list')).toContainText('OLD9');
  await expect(page.locator('#stat-matched')).toHaveText('0');
  await expect(page.locator('#stat-unexpected')).toHaveText('0');
  await expect.poll(() => calls.find(c => c.method === 'POST' && c.name === 'inventory_count_scans')).toBeTruthy();
  const saved = JSON.parse(calls.find(c => c.method === 'POST' && c.name === 'inventory_count_scans').body);
  expect(saved.match_status).toBe('cancelled');
});
