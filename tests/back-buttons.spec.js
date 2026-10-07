// Every page's back arrow leaves the page (no loops back onto itself), and the
// customer/trader flows step back the way the user came.
const { test, expect } = require('@playwright/test');
const fs = require('fs'), path = require('path');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const root = path.resolve(__dirname, '..');
const pages = fs.readdirSync(root).filter(f => f.endsWith('.html') && !/_\d+\.html$|^index-ar_3|^logo-preview|^login-ar-4/.test(f))
  .filter(f => /onclick="(gmSmartBack|goBack|headerBack)/.test(fs.readFileSync(path.join(root, f), 'utf8')));
const BACK = '[onclick^="gmSmartBack"], [onclick^="goBack"], [onclick^="headerBack"]';

for (const file of pages) {
  test(`back leaves: ${file}`, async ({ page }) => {
    page.on('dialog', d => d.accept().catch(() => {}));
    await install(page, { generic: true });
    await page.goto('/index-ar.html');
    await page.goto('/' + file, { waitUntil: 'load' }).catch(() => {});
    await page.waitForTimeout(900);
    const here = new URL(page.url()).pathname;
    const btn = page.locator(BACK).first();
    if (!(await btn.isVisible().catch(() => false))) test.skip(true, 'no visible back button without data');
    await btn.click({ timeout: 3000 }).catch(() => {});
    await page.waitForTimeout(900);
    // a page may close an inner view first; a second press must leave
    if (new URL(page.url()).pathname === here) { await page.locator(BACK).first().click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(900); }
    expect(new URL(page.url()).pathname, file).not.toBe(here);
  });
}

const db = () => ({
  stores: [{ id: STORE, name: 'x', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'حسن درويش' }], customer_debts: [], invoices: [],
  traders: [{ id: 't1', store_id: STORE, name: 'جليل' }], trader_movements: []
});
const path_ = p => new URL(p.url()).pathname + new URL(p.url()).search;

test('home → customers → customer → back → back', async ({ page }) => {
  await install(page, { generic: true, db: db() });
  await page.goto('/index-ar.html');
  await page.goto('/customers-ar.html');
  await page.goto('/customer-debts-ar.html?open=c1');
  await page.waitForTimeout(800);
  await page.click(BACK); await page.waitForURL(/customers-ar\.html/);
  await page.waitForTimeout(500);
  await page.click(BACK); await page.waitForURL(/index-ar\.html/);
});

test('old "ديون العملاء" link forwards to customers and back goes home', async ({ page }) => {
  await install(page, { generic: true, db: db() });
  await page.goto('/index-ar.html');
  await page.goto('/customer-debts-ar.html');
  await page.waitForURL(/customers-ar\.html/);
  await page.waitForTimeout(500);
  await page.click(BACK); await page.waitForURL(/index-ar\.html/);
  expect(path_(page)).toContain('index-ar.html');
});

test('trader opened from another page goes back there', async ({ page }) => {
  await install(page, { generic: true, db: db() });
  await page.goto('/index-ar.html');
  await page.goto('/cash-voucher-ar.html');
  await page.goto('/ledger-ar.html?trader=t1');
  await page.waitForTimeout(800);
  await page.click(BACK); await page.waitForURL(/cash-voucher-ar\.html/);
});
