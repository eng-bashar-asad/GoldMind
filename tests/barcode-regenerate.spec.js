// Regenerating a piece's barcode: confirm first, the old number is cancelled in counts.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('changing the chip keeps the barcode, saves a new chip number and the old one', async ({ page }) => {
  let asked = null; // the first dialog is the confirmation
  page.on('dialog', d => { if (asked === null) asked = d.message(); d.accept(); });
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED', rfid_enabled: true, rfid_device_key: 'dev-1' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000100', status: 'available', weight_grams: 10, karat: 18 }],
  }, rpc: { replace_piece_chip: (args) => ({ body: args.p_new_epc }) } });
  await page.goto('/piece-edit-ar.html?id=p1');
  await page.waitForFunction(() => typeof currentPiece !== 'undefined' && currentPiece && currentPiece.barcode);
  await page.evaluate(() => { GMUhf.available = async () => true; GMUhf.writeEpc = async () => {}; });
  await page.evaluate(() => gmReprogramChip(document.getElementById('gmRechipBtn')));
  await expect.poll(() => calls.some(c => c.kind === 'rest/v1/rpc' && c.name === 'replace_piece_chip')).toBe(true);
  const body = JSON.parse(calls.find(c => c.kind === 'rest/v1/rpc' && c.name === 'replace_piece_chip').body);
  expect(body.p_piece_id).toBe('p1');
  expect(body.p_new_epc).toMatch(/^[0-9A-F]{24}$/);
  expect(body.p_old_epc).toMatch(/^[0-9A-F]{24}$/);
  expect(body.p_new_epc).not.toBe(body.p_old_epc);
  expect(asked).toContain('000100');
  expect(asked).toContain('الباركود ما بيتغيّر');
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

test('a replaced chip number is listed as cancelled in an RFID count', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const OLD = 'A1B2C3D4E5F6A7B8C9D0E1F2', NEW = '0F1E2D3C4B5A69788796A5B4';
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: true, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, status: 'available', barcode: 'A1', rfid_epc: NEW, karat: 18, weight_grams: 5 }],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'in_progress', method: 'rfid', scope: ['gold'], started_at: '2026-10-13T10:00:00Z', expected_piece_count: 1 }],
    inventory_count_expected: [{ count_id: 'k1', piece_id: 'p1', piece_source: 'gold', barcode: 'A1', match_value: NEW, karat: 18, weight_grams: 5 }],
    inventory_count_scans: [],
    piece_chip_history: [{ store_id: STORE, old_epc: OLD, new_epc: NEW, piece_id: 'p1', pieces: { barcode: 'A1', description_ar: 'خاتم' } }],
  } });
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); }; });
  await page.goto('/inventory-count-ar.html');
  await page.waitForFunction(() => typeof inProgressSession !== 'undefined' && inProgressSession);
  await page.click('text=استئناف الجلسة');
  await expect(page.locator('#scan-wrap')).not.toHaveClass(/\bhidden\b/);
  await page.evaluate(([v]) => handleScan(v, 'rfid'), [OLD]);
  await expect(page.locator('#cancelled-count')).toHaveText('1');
  await expect(page.locator('#stat-matched')).toHaveText('0');
  await expect(page.locator('#stat-unexpected')).toHaveText('0');
  await expect.poll(() => calls.some(c => c.method === 'POST' && c.name === 'inventory_count_scans')).toBe(true);
});
