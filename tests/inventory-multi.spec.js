// Two phones scanning one inventory count together.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const STAFF2 = '00000000-0000-4000-8000-0000000000b2';
const COUNT = '00000000-0000-4000-8000-00000000c001';

function db(me = STAFF) {
  return {
    stores: [{ id: STORE, rfid_enabled: true, diamonds_enabled: false }],
    // Both phones log in as the same test user; each phone's db decides which employee that is.
    staff: [{ id: STAFF, user_id: me === STAFF ? USER : 'other', store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' },
            { id: STAFF2, user_id: me === STAFF2 ? USER : 'other', store_id: STORE, role: 'owner', permissions: {}, full_name: 'أحمد' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [],
    inventory_counts: [{ id: COUNT, store_id: STORE, status: 'in_progress', method: 'rfid', scope: ['gold'], started_at: '2026-09-27T08:00:00Z', expected_piece_count: 3 }],
    inventory_count_expected: ['E1', 'E2', 'E3'].map((v, i) => ({ count_id: COUNT, piece_id: 'p' + i, piece_source: 'gold', match_value: v, barcode: 'GM-' + v, karat: 18, weight_grams: 5 })),
  };
}

// One shared scans table for both phones, with the same unique rule as the database.
function shareScans(page, scans) {
  return page.route(/\.supabase\.co\/rest\/v1\/inventory_count_scans/, async route => {
    const req = route.request(), url = new URL(req.url());
    if (req.method() === 'POST') {
      const row = JSON.parse(req.postData());
      const r = Array.isArray(row) ? row[0] : row;
      if (scans.some(s => s.count_id === r.count_id && s.rfid_epc === r.rfid_epc)) {
        return route.fulfill({ status: 409, json: { code: '23505', message: 'duplicate key' } });
      }
      scans.push({ ...r, scanned_at: new Date().toISOString() });
      return route.fulfill({ status: 201, json: [] });
    }
    let rows = scans.slice();
    url.searchParams.forEach((expr, key) => {
      const [op, ...rest] = expr.split('.'); const val = rest.join('.');
      if (op === 'eq') rows = rows.filter(r => String(r[key]) === val);
      if (op === 'neq') rows = rows.filter(r => String(r[key]) !== val);
      if (op === 'gte') rows = rows.filter(r => r[key] >= decodeURIComponent(val));
    });
    const single = (req.headers()['accept'] || '').includes('vnd.pgrst.object');
    return route.fulfill({ json: single ? (rows[0] || null) : rows });
  });
}

async function openPhone(context, scans, staffId) {
  const page = await context.newPage();
  await install(page, { db: db(staffId) });
  if (staffId !== STAFF) {
    await page.addInitScript(([user, store, staff]) => {
      localStorage.setItem('gm_membership', JSON.stringify({ user, store, staff }));
    }, [USER, STORE, staffId]);
  }
  await shareScans(page, scans);
  page.on('dialog', d => d.accept());
  page.on('pageerror', e => console.log('PAGEERR', e.message));
  await page.goto('/inventory-count-ar.html');
  await expect(page.locator('#resume-details')).toHaveText(/RFID/);
  await page.click('text=استئناف الجلسة');
  await expect(page.locator('#stat-expected')).toHaveText('3');
  return page;
}

async function scan(page, v) {
  await page.fill('#scan-input', v);
  await page.press('#scan-input', 'Enter');
}

test('two phones share one count: no double counting, one full report', async ({ browser }) => {
  test.setTimeout(90000);
  const scans = [];
  const ctxA = await browser.newContext(), ctxB = await browser.newContext();
  const a = await openPhone(ctxA, scans, STAFF);
  const b = await openPhone(ctxB, scans, STAFF2);

  await scan(a, 'E1');
  await scan(b, 'E2');
  // Each phone sees the other's scan (live, or the 8-second fallback sync).
  await expect(a.locator('#stat-scanned')).toHaveText('2', { timeout: 15000 });
  await expect(b.locator('#stat-scanned')).toHaveText('2', { timeout: 15000 });
  await expect(a.locator('#scan-by-people')).toContainText('أحمد: 1');

  // Scanning a piece the colleague already did is refused and names them.
  await scan(b, 'E1');
  await expect(b.locator('#last-scan-box')).toContainText('بشار');
  await expect(b.locator('#stat-scanned')).toHaveText('2');

  // Race: B saved E3 but A hasn't synced yet — A's save is refused by the rule, still counted once.
  scans.push({ count_id: COUNT, store_id: STORE, rfid_epc: 'E3', scanned_by: STAFF2, match_status: 'matched', scanned_at: new Date().toISOString() });
  await scan(a, 'E3');
  await expect(a.locator('#stat-scanned')).toHaveText('3');
  expect(scans.filter(s => s.rfid_epc === 'E3')).toHaveLength(1);

  // Finishing on A collects everyone's scans: nothing missing.
  await a.click('#finish-btn');
  await expect(a.locator('#report-wrap')).toBeVisible();
  await expect(a.locator('#report-scanned')).toHaveText('3');
  await expect(a.locator('#report-missing-count')).toHaveText('0');
  expect(scans).toHaveLength(3);
});

test('report lists show each piece photo, and why a surplus scan was surplus', async ({ browser }) => {
  const scans = [];
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const base = db(STAFF);
  base.pieces = [
    { id: 'p1', store_id: STORE, barcode: 'GM-E2', rfid_epc: 'E2', status: 'available', description_ar: 'سوار', photo_url: 'http://localhost:4173/icon-192.png' },
    { id: 'p2', store_id: STORE, barcode: 'GM-E3', rfid_epc: 'E3', status: 'available', description_ar: 'خاتم', photo_url: null },
    { id: 'ps', store_id: STORE, barcode: 'GM-S1', rfid_epc: 'S1', status: 'sold', description_ar: 'عقد', photo_url: 'http://localhost:4173/icon-512.png' },
  ];
  await install(page, { db: base });
  await shareScans(page, scans);
  page.on('dialog', d => d.accept());
  await page.goto('/inventory-count-ar.html');
  await expect(page.locator('#resume-details')).toHaveText(/RFID/);
  await page.click('text=استئناف الجلسة');
  await expect(page.locator('#stat-expected')).toHaveText('3');
  await scan(page, 'E1');
  await scan(page, 'S1');      // sold piece still in the shop
  await scan(page, 'ZZ9');     // unknown tag
  await page.click('#finish-btn');
  await expect(page.locator('#report-missing-count')).toHaveText('2');

  await page.click("button[onclick=\"openSubScreen('missing')\"]");
  const missing = page.locator('#subscreen-list > div');
  await expect(missing).toHaveCount(2);
  await expect(missing.nth(0).locator('img')).toHaveAttribute('src', /icon-192/);
  await expect(missing.nth(1).locator('img')).toHaveCount(0);   // no photo -> placeholder
  await expect(missing.nth(1)).toContainText('خاتم');

  await page.evaluate(() => closeSubScreen());
  await page.click("button[onclick=\"openSubScreen('surplus')\"]");
  const surplus = page.locator('#subscreen-list > div');
  await expect(surplus).toHaveCount(2);
  await expect(surplus.filter({ hasText: 'S1' })).toContainText('حالتها: مباعة');
  await expect(surplus.filter({ hasText: 'S1' }).locator('img')).toHaveAttribute('src', /icon-512/);
  await expect(surplus.filter({ hasText: 'ZZ9' })).toContainText('غير مسجّلة في النظام');
  if (process.env.UI_OUT) await page.screenshot({ path: process.env.UI_OUT + '/surplus.png' });
});
