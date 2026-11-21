// Long lists draw 60 at a time; «عرض المزيد» (or scrolling to it) adds the next page. Customers past 300 are reachable.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const base = { stores: [{ id: STORE, name: 'x', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] };
test('customers: 350 on the phone, all reachable', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await install(page, { generic: false, db: { ...base, customers: Array.from({ length: 350 }, (_, i) => ({ id: 'c' + i, store_id: STORE, name: 'عميل ' + String(i).padStart(3, '0'), phone: '05' + i })), customer_debts: [] } });
  await page.goto('/customers-ar.html');
  const cards = page.locator('#list > div');
  await expect(cards).toHaveCount(60);
  const more = page.locator('#list .gm-more');
  await expect(more).toContainText('290');
  for (let i = 0; i < 5; i++) await page.evaluate(() => { const b = document.querySelector('#list .gm-more'); b && gmShowMore(b); });
  await expect(cards).toHaveCount(350);
  await expect(more).toHaveCount(0);
});
test('customers table on the computer pages by 100 and rows still open the side card', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await install(page, { generic: false, db: { ...base, customers: Array.from({ length: 230 }, (_, i) => ({ id: 'c' + i, store_id: STORE, name: 'عميل ' + i })), customer_debts: [] } });
  await page.goto('/customers-ar.html');
  const rows = page.locator('#list tbody tr');
  await expect(rows).toHaveCount(100);
  while (await page.locator('#list .gm-more').count()) await page.locator('#list .gm-more').click(); // (scrolling to it also loads)
  await expect(rows).toHaveCount(230);
  await rows.nth(220).click();
  await expect(page.locator('#cuSide')).toContainText('عميل');
});
