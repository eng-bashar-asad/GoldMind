// A closed count stays editable (found piece, delete a wrong scan) until the owner posts it;
// posting locks it. Staff without the owner role can edit but not post (Bashar 2026-11-01).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

function db(role) {
  return {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role, permissions: { run_inventory_count: true }, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [
      { id: 'p1', store_id: STORE, status: 'available', barcode: 'A1', karat: 18, weight_grams: 5 },
      { id: 'p2', store_id: STORE, status: 'available', barcode: 'A2', karat: 21, weight_grams: 7 },
    ],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'completed', method: 'camera', scope: ['gold'], started_at: '2026-09-28T10:00:00Z', completed_at: '2026-09-28T11:00:00Z', expected_piece_count: 2 }],
    inventory_count_expected: [
      { count_id: 'k1', piece_id: 'p1', piece_source: 'gold', barcode: 'A1', match_value: 'A1', karat: 18, weight_grams: 5 },
      { count_id: 'k1', piece_id: 'p2', piece_source: 'gold', barcode: 'A2', match_value: 'A2', karat: 21, weight_grams: 7 },
    ],
    inventory_count_scans: [
      { id: 's1', count_id: 'k1', store_id: STORE, rfid_epc: 'A1', match_status: 'matched', scanned_by: STAFF, scanned_at: '2026-09-28T10:01:00Z' },
      { id: 's2', count_id: 'k1', store_id: STORE, rfid_epc: 'ZZ9', match_status: 'unexpected', scanned_by: STAFF, scanned_at: '2026-09-28T10:02:00Z' },
    ],
  };
}

async function openClosedCount(page, role) {
  page.on('dialog', d => d.accept());
  const calls = await install(page, { db: db(role) });
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); }; });
  await page.goto('/inventory-count-ar.html');
  await page.locator('#past-sessions-list button').first().click();
  await expect(page.locator('#session-detail-wrap')).not.toHaveClass(/\bhidden\b/);
  return calls;
}

test('closed count: found piece, delete a wrong scan, then the owner posts and it locks', async ({ page }) => {
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  const calls = await openClosedCount(page, 'owner');
  await expect(page.locator('#sd-missing')).toHaveText('1');
  await expect(page.locator('#sd-surplus')).toHaveText('1');
  await expect(page.locator('#sd-balanced')).toHaveClass(/\bhidden\b/);

  await page.locator('#sd-p-missing button:has-text("وُجدت")').click();
  await expect(page.locator('#sd-missing')).toHaveText('0');
  const add = calls.find(c => c.method === 'POST' && c.name === 'inventory_count_scans');
  expect(JSON.parse(add.body)).toMatchObject({ count_id: 'k1', rfid_epc: 'A2', match_status: 'matched', scan_method: 'manual' });

  await page.locator('#sd-p-surplus button[aria-label="حذف المسحة"]').click();
  await expect(page.locator('#sd-surplus')).toHaveText('0');
  expect(calls.some(c => c.method === 'DELETE' && c.name === 'inventory_count_scans' && c.url.includes('id=eq.s2'))).toBe(true);
  await expect(page.locator('#sd-balanced')).not.toHaveClass(/\bhidden\b/);

  await page.click('#post-count-btn');
  const post = calls.find(c => c.method === 'PATCH' && c.name === 'inventory_counts' && /posted/.test(c.body || ''));
  expect(JSON.parse(post.body)).toMatchObject({ status: 'posted' });
  expect(errors).toEqual([]);
});

test('closed count: staff can edit, only the owner can post', async ({ page }) => {
  await openClosedCount(page, 'staff');
  await expect(page.locator('#post-count-btn')).toHaveCount(0);
  await expect(page.locator('#session-edit-hint')).toContainText('بيد المدير');
  await expect(page.locator('#sd-p-missing button:has-text("وُجدت")')).toHaveCount(1);
});
