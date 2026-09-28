// Owner sees who is online; typing "123" finds barcode "000123".
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const SHOT = process.env.UI_OUT;
const now = new Date().toISOString(), old = new Date(Date.now() - 3 * 3600e3).toISOString();
function db(role) {
  return {
    stores: [{ id: STORE, name: 'مجوهرات', currency: 'USD' }],
    staff: [
      { id: STAFF, user_id: USER, store_id: STORE, role, permissions: { view_inventory: true }, full_name: 'بشار' },
      { id: 's2', store_id: STORE, role: 'staff', full_name: 'ربا', permissions: {} },
      { id: 's3', store_id: STORE, role: 'staff', full_name: 'محمد', permissions: {} },
    ],
    staff_presence: [
      { staff_id: 's2', store_id: STORE, last_seen_at: now, last_page: 'inventory-list-ar.html' },
      { staff_id: 's3', store_id: STORE, last_seen_at: old, last_page: 'index-ar.html' },
    ],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [
      { id: 'p1', store_id: STORE, status: 'available', barcode: '000123', karat: 18, weight_grams: 5, created_at: now },
      { id: 'p2', store_id: STORE, status: 'available', barcode: '000456', karat: 21, weight_grams: 7, created_at: now },
    ],
  };
}

test('owner: online box, list, and heartbeat', async ({ page }) => {
  const calls = await install(page, { db: db('owner'), realCdn: !!SHOT });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/index-ar.html');
  await expect(page.locator('#gmOnlineCount')).toHaveText('1');
  await expect(page.locator('#gmOnlineBtn')).not.toHaveClass(/\bhidden\b/);
  expect(calls.some(c => c.name === 'staff_heartbeat' && JSON.parse(c.body).p_store === STORE)).toBe(true);
  if (SHOT) await page.screenshot({ path: SHOT + '/online1.png' });
  await page.click('#gmOnlineBtn');
  await expect(page.locator('#gmOnlineList')).toContainText('ربا');
  await expect(page.locator('#gmOnlineList')).toContainText('متصل الآن — المخزن');
  await expect(page.locator('#gmOnlineList')).toContainText('آخر ظهور قبل 3 ساعات');
  if (SHOT) await page.screenshot({ path: SHOT + '/online2.png' });
});

test('staff: no online box', async ({ page }) => {
  await install(page, { db: db('staff') });
  await page.goto('/index-ar.html');
  await page.waitForTimeout(1500);
  await expect(page.locator('#gmOnlineBtn')).toHaveClass(/\bhidden\b/);
});

test('search "123" finds barcode 000123 (home search -> inventory)', async ({ page }) => {
  await install(page, { db: db('staff') });
  await page.goto('/index-ar.html');
  await page.evaluate(() => openQuickSearch());
  await page.fill('#quickSearchInput', '123');
  await page.click('text=ابحث عن القطعة');
  await expect(page).toHaveURL(/inventory-list-ar\.html\?q=123/);
  await expect(page.locator('#search-results-list')).toContainText('000123');
  await expect(page.locator('#search-results-list')).not.toContainText('000456');
});

test('new sale: barcode "123" adds piece 000123', async ({ page }) => {
  await install(page, { db: db('owner') });
  await page.goto('/new-sale-ar.html?barcode=123');
  await expect(page.locator('#barcode-result')).toContainText('000123');
});

test('inventory search copes with phone keyboards (Arabic digits, hidden marks)', async ({ page }) => {
  await install(page, { db: db('staff') });
  await page.goto('/inventory-list-ar.html');
  await page.waitForFunction(() => document.getElementById('piece-count') && typeof runSearch === 'function');
  for (const q of ['‏000123', '١٢٣', '000123']) {
    await page.evaluate(v => { document.getElementById('search-barcode').value = v; runSearch(); }, q);
    await expect(page.locator('#search-results-list')).toContainText('000123');
  }
});
