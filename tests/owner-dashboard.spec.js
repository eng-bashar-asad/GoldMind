// Multi-branch 3.2: the owner's dashboard — one card per owned store, grouped by company, each in its currency.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('owner dashboard groups stores by company and shows their numbers', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const row = (id, name, org, oname, cur, extra) => Object.assign({ store_id: id, store_name: name, organization_id: org, organization_name: oname, is_head: true, currency: cur,
    today_sales: 0, today_invoices: 0, month_sales: 0, drawer: {}, stock_pieces: 0, stock: {}, scrap: {}, customers_owe: 0, customers_owing: 0, traders_gold24: 0, traders_cash: 0, incoming_transfers: 0 }, extra || {});
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  }, rpc: { owner_dashboard: () => ({ body: [
    row(STORE, 'Ahmad Al Khayat Mall', 'o1', 'Ahmad Al Khayat', 'USD', { today_sales: 1500, today_invoices: 2, month_sales: 327025.15, drawer: { USD: 34998, SYP: 18716000 }, stock_pieces: 730, stock: { 18: 10576.97 }, scrap: { 18: 85.81 }, customers_owe: 77136.64, customers_owing: 11, traders_gold24: 1721.9, traders_cash: -120 }),
    row('s2', 'Ahmad Al Khayat Sharjah', 'o2', 'Ahmad Al Khayat Jewellery', 'AED', { incoming_transfers: 1 }),
  ] }) } });
  await page.goto('/owner-dashboard-ar.html');
  const list = page.locator('#od-list');
  await expect(list.locator('section')).toHaveCount(2);
  await expect(list.locator('h2')).toHaveCount(2);
  const mall = list.locator('section').first();
  await expect(mall).toContainText('327,025.15');
  await expect(mall).toContainText('77,136.64');
  await expect(mall).toContainText('18,716,000.00');
  await expect(mall).toContainText('10576.97 g');
  await expect(mall).toContainText('علينا'); // trader cash −120: the shop owes
  await expect(list.locator('section').nth(1)).toContainText('1 نقل وارد');
  // «فتح الفرع» makes that store the active one and goes home
  await page.evaluate(() => { window.goldMindSetActiveStore = id => { window.__picked = id; }; });
  await list.locator('section').nth(1).locator('button', { hasText: 'فتح الفرع' }).click();
  expect(await page.evaluate(() => window.__picked)).toBe('s2');
  expect(errs).toEqual([]);
});
