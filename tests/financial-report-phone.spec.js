// بشار 2026-11-23: on the phone the financial report slid sideways (a wide table pushed the page).
// Wide tables now scroll inside their own card; the page itself never scrolls sideways.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('financial report: a wide table never pushes the page sideways', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], invoices: [], expense_entries: [] } });
  await page.goto('/financial-report-ar.html');
  await expect(page.locator('.fr-in').first()).toBeAttached({ timeout: 8000 });
  const r = await page.evaluate(async () => {
    const box = document.querySelector('.fr-in'), d = document.createElement('div');
    d.style.cssText = 'width:900px;height:10px'; box.appendChild(d);
    window.scrollTo(-400, 0); window.scrollTo(400, 0); await new Promise(res => setTimeout(res, 100));
    return { pageX: window.scrollX, boxScrolls: getComputedStyle(box).overflowX };
  });
  expect(r.pageX).toBe(0);
  expect(r.boxScrolls).toBe('auto');
});
