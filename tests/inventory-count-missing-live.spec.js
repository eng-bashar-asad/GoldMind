// During a count: a button shows only the pieces not scanned yet, with photo and details.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('scan screen: missing pieces with photos, found button', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const P = (id, bc, status, extra) => ({ id, store_id: STORE, barcode: bc, status, weight_grams: 12.5, accounting_weight_grams: 12.1, karat: 18, piece_type: 'إسوارة', box_name: 'قطع ذهبية', color: 'Gold', photo_url: 'https://example.com/' + bc + '.jpg', ...extra });
  const E = (id, bc) => ({ count_id: 'k1', piece_id: id, piece_source: 'gold', barcode: bc, match_value: bc, karat: 18, weight_grams: 12.5 });
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [P('p1', '000001', 'available'), P('p2', '000002', 'available'), P('p3', '000003', 'gifted'), P('p4', '000004', 'reserved')],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'in_progress', method: 'camera', scope: ['gold'], started_at: '2026-09-27T09:00:00Z', expected_piece_count: 4 }],
    inventory_count_expected: [E('p1', '000001'), E('p2', '000002'), E('p3', '000003'), E('p4', '000004')],
    inventory_count_scans: [{ id: 's1', count_id: 'k1', store_id: STORE, rfid_epc: '000001', match_status: 'matched', scanned_by: STAFF, scanned_at: '2026-09-27T09:01:00Z' }],
  } });
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); }; });
  await page.route(/example\.com/, r => r.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>' }));
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/inventory-count-ar.html');
  await page.waitForFunction(() => typeof inProgressSession !== 'undefined' && inProgressSession);
  await page.click('text=استئناف الجلسة');
  await expect(page.locator('#missing-live-label')).toHaveText('القطع الناقصة مع الصور (3)');
  await page.click('#missing-live-btn');
  const w = page.locator('#missing-live-wrap');
  await expect(w).toContainText('ناقصة فعلاً: 2 قطعة');                 // 000002 + reserved 000004
  await expect(w.locator('img[alt="صورة القطعة"]')).toHaveCount(2);
  await expect(w).toContainText('الوزن 12.50 غ · محاسبة 12.10 غ');
  await expect(w).toContainText('الصندوق: قطع ذهبية');
  await expect(w).toContainText('خرجت من المخزن بعد بدء الجرد: 1');     // gift 000003
  await w.locator('button:has-text("وُجدت")').first().click();
  await expect(w).toContainText('ناقصة فعلاً: 1 قطعة');
  await expect(page.locator('#missing-live-label')).toHaveText('القطع الناقصة مع الصور (2)');
  const ins = calls.find(c => c.method === 'POST' && c.name === 'inventory_count_scans');
  expect(JSON.parse(ins.body)).toMatchObject({ rfid_epc: '000002', match_status: 'matched', scan_method: 'manual' });
  expect(errs).toEqual([]);
});

test('missing pieces sheet: big photos, barcode, weight, karat; PDF', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const P = (id, bc, status, extra) => ({ id, store_id: STORE, barcode: bc, status, weight_grams: 12.5, accounting_weight_grams: 12.1, karat: 18, piece_type: 'إسوارة', box_name: 'قطع ذهبية', color: 'Gold', photo_url: 'https://example.com/' + bc + '.jpg', ...extra });
  const E = (id, bc) => ({ count_id: 'k1', piece_id: id, piece_source: 'gold', barcode: bc, match_value: bc, karat: 18, weight_grams: 12.5 });
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'x', rfid_enabled: false, diamonds_enabled: false }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [P('p1', '000001', 'available'), P('p2', '000002', 'available'), P('p3', '000003', 'gifted'), P('p4', '000004', 'reserved')],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'in_progress', method: 'camera', scope: ['gold'], started_at: '2026-09-27T09:00:00Z', expected_piece_count: 4 }],
    inventory_count_expected: [E('p1', '000001'), E('p2', '000002'), E('p3', '000003'), E('p4', '000004')],
    inventory_count_scans: [{ id: 's1', count_id: 'k1', store_id: STORE, rfid_epc: '000001', match_status: 'matched', scanned_by: STAFF, scanned_at: '2026-09-27T09:01:00Z' }],
  } });
  await page.addInitScript(() => { window.Html5QrcodeSupportedFormats = {}; window.Html5Qrcode = function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); }; });
  await page.route(/example\.com/, r => r.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>' }));
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/inventory-count-ar.html');
  await page.waitForFunction(() => typeof inProgressSession !== 'undefined' && inProgressSession);
  await page.click('text=استئناف الجلسة');
  await expect(page.locator('#missing-live-label')).toHaveText('القطع الناقصة مع الصور (3)');
  await page.click('#missing-live-btn');
  const w = page.locator('#missing-live-wrap');
  await expect(w).toContainText('ناقصة فعلاً: 2 قطعة');                 // 000002 + reserved 000004
  await expect(w.locator('img[alt="صورة القطعة"]')).toHaveCount(2);
  await expect(w).toContainText('الوزن 12.50 غ · محاسبة 12.10 غ');
  await expect(w).toContainText('الصندوق: قطع ذهبية');
  await expect(w).toContainText('خرجت من المخزن بعد بدء الجرد: 1');     // gift 000003
  await expect(w.locator('button:has-text("طباعة الناقص بالصور")')).toBeVisible();
  const items = await page.evaluate(() => gmMissingSheetItems);
  expect(items.map(i => [i.barcode, i.weight, i.karat])).toEqual([['000002', 12.5, 18], ['000004', 12.5, 18]]);
  const html = await page.evaluate(() => gmMissingSheetPages(gmMissingSheetItems, 't').map(p => p.innerHTML).join(''));
  expect(html).toContain('000002');
  expect(html).toContain('الوزن القائم: <bdi dir="ltr">12.50</bdi> غ · عيار 18');
  expect(html).toContain('repeat(4,1fr)');
  await page.route(/html2pdf/, r => r.fulfill({ contentType: 'text/javascript', body: require('fs').readFileSync(require('path').join(__dirname, 'node_modules/html2pdf.js/dist/html2pdf.bundle.min.js'), 'utf8') }));
  await page.route(/html2canvas/, r => r.fulfill({ contentType: 'text/javascript', body: require('fs').readFileSync(require('path').join(__dirname, 'node_modules/html2canvas/dist/html2canvas.min.js'), 'utf8') }));
  await page.evaluate(() => { window.gmSavePdf = async (w, name) => { const pdf = await w.get('pdf'); window.__pdf = { name, pages: pdf.internal.getNumberOfPages() }; }; });
  await w.locator('button:has-text("PDF")').click();
  await page.waitForFunction(() => window.__pdf, null, { timeout: 20000 });
  expect((await page.evaluate(() => window.__pdf)).pages).toBe(1);
  expect(errs).toEqual([]);
});
