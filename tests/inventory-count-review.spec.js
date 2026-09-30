// Reopening a finished count shows what is really missing vs what left stock,
// lets you mark a found piece and clear misread codes, with gold totals.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('past count review: real missing, left stock, misreads, totals', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const P = (id, bc, status, w, aw, fab) => ({ id, store_id: STORE, barcode: bc, status, weight_grams: w, accounting_weight_grams: aw, cost_fabrication_per_gram: fab, karat: 18, piece_type: 'خاتم' });
  const pieces = [P('p1', '000001', 'available', 10, 9, 5), P('p2', '000002', 'available', 20, 19, 6), P('p3', '000003', 'available', 5, 5, 4),
    P('p4', '000004', 'reserved', 7, 7, 4), P('p5', '000005', 'sold', 8, 8, 4), P('p6', '000006', 'gifted', 3, 3, 4), P('p8', '000008', 'sold', 4, 4, 4)];
  const E = (id, bc) => ({ count_id: 'k1', piece_id: id, piece_source: 'gold', barcode: bc, match_value: bc, karat: 18, weight_grams: 1 });
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces,
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'completed', method: 'camera', scope: ['gold'], started_at: '2026-09-27T09:00:00Z', expected_piece_count: 7, matched_count: 2, missing_count: 5, unexpected_count: 3 }],
    inventory_count_expected: [E('p1', '000001'), E('p2', '000002'), E('p3', '000003'), E('p4', '000004'), E('p5', '000005'), E('p6', '000006'), E('p7', '000007')],
    inventory_count_scans: [
      { id: 's1', count_id: 'k1', store_id: STORE, rfid_epc: '000001', match_status: 'matched', scanned_at: '2026-09-27T09:01:00Z' },
      { id: 's2', count_id: 'k1', store_id: STORE, rfid_epc: '000002', match_status: 'matched', scanned_at: '2026-09-27T09:02:00Z' },
      { id: 's3', count_id: 'k1', store_id: STORE, rfid_epc: '(002/(', match_status: 'unexpected', scanned_at: '2026-09-27T09:03:00Z' },
      { id: 's4', count_id: 'k1', store_id: STORE, rfid_epc: 'zzzz20', match_status: 'unexpected', scanned_at: '2026-09-27T09:04:00Z' },
      { id: 's5', count_id: 'k1', store_id: STORE, rfid_epc: '000008', match_status: 'unexpected', scanned_at: '2026-09-27T09:05:00Z' },
    ],
  } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/inventory-count-ar.html');
  // previous sessions are on the first screen now
  const row = page.locator('#past-sessions-list button').first();
  await expect(row).toContainText('ناقصة');
  await row.click();
  const rv = page.locator('#sd-review');
  await expect(rv).toContainText('ناقصة فعلاً (2)');                       // p3 available + p4 reserved
  await expect(rv).toContainText('خرجت من المخزن بعد بدء الجرد (3)');      // p5 sold, p6 gift, p7 deleted
  await expect(rv).toContainText('محذوفة من البرنامج');
  await expect(rv).toContainText('زيادة (3)');
  await expect(rv).toContainText('حذف كل الرموز غير الموجودة في النظام (2)');
  await expect(rv).toContainText('ذهب القطع التي وُجدت بالجرد (2 قطعة)');
  await expect(rv).toContainText('30.00');   // gross 10 + 20
  await expect(rv).toContainText('28.00');   // accounting 9 + 19
  await expect(rv).toContainText('159.00');  // fab 9×5 + 19×6
  // mark the found piece
  await rv.locator('button:has-text("وُجدت")').first().click();
  await expect(rv).toContainText('ناقصة فعلاً (1)');
  const ins = calls.find(c => c.method === 'POST' && c.name === 'inventory_count_scans');
  expect(JSON.parse(ins.body)).toMatchObject({ count_id: 'k1', rfid_epc: '000003', match_status: 'matched', scan_method: 'manual' });
  // clear the misread codes
  await rv.locator('button:has-text("حذف كل الرموز")').click();
  await expect(rv).toContainText('زيادة (1)');
  expect(calls.some(c => c.method === 'DELETE' && c.name === 'inventory_count_scans' && /s3/.test(c.url) && /s4/.test(c.url))).toBe(true);
  expect(errs).toEqual([]);
});

test('count photo opens in its own page', async ({ page }) => {
  await page.setContent('<div></div>');
  await page.addScriptTag({ content: require('fs').readFileSync(require('path').join(__dirname, '..', 'inventory-count-ar.html'), 'utf8').match(/function gmCountPhoto[^\n]*\n/)[0] });
  const args = await page.evaluate(() => { let a; window.open = (...x) => { a = x; }; gmCountPhoto('https://x.test/p.jpg'); return a; });
  expect(args.slice(0, 2)).toEqual(['https://x.test/p.jpg', '_blank']);
});
