// While a list loads, its loading box shows shimmering placeholder rows; they go away when the data arrives.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const base = { stores: [{ id: STORE, name: 'x', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'سارة' }], customer_debts: [] };
for (const url of ['/customers-ar.html', '/invoices-list-ar.html', '/daily-cashbox-ar.html', '/inventory-list-ar.html']) {
  test(`skeleton on ${url}`, async ({ page }) => {
    await install(page, { generic: true, db: base });
    await page.route(/rest\/v1\/(customers|invoices|daily_cash_log|pieces)\?/, async r => { await new Promise(res => setTimeout(res, 1500)); await r.fallback(); });
    await page.goto(url);
    await expect(page.locator('#loading-state .gm-skel .gm-sk-row').first()).toBeVisible();
    await expect(page.locator('#loading-state')).toHaveClass(/hidden/, { timeout: 10000 }); // (Tailwind isn't loaded in tests, so check the class)
  });
}
