// Daily box (redesign 2026-10-31): one chronological list with the balance after each row,
// in/out tiles, filters that only hide rows, a total line; on the phone the rows are cards.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const at = m => { const d = new Date(); d.setHours(0, 0, 0, 0); return new Date(d.getTime() + m * 60000).toISOString(); };
const yesterday = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return new Date(d.getTime() - 3600000).toISOString(); };
const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  daily_cash_log: [
    { id: 'o', store_id: STORE, direction: 'in', amount: 1000, currency: 'USD', operation_type: 'رصيد سابق', created_at: yesterday() },
    { id: 'a', store_id: STORE, direction: 'in', amount: 500, currency: 'USD', operation_type: 'مبيعات لـ هلا', cash_movement_id: 'c1', cm: { invoice_id: 'i1' }, created_at: at(1) },
    { id: 'b', store_id: STORE, direction: 'out', amount: 200, currency: 'USD', operation_type: 'مصروف ضيافة', created_at: at(2) },
  ],
});

test('computer: balance after each row, tiles, filters, totals', async ({ page }) => {
  await install(page, { db: db() });
  await page.goto('/daily-cashbox-ar.html');
  const rows = page.locator('#cashbox-table-body > tr');
  await expect(rows).toHaveCount(2);
  await expect(rows.nth(0).locator('.dc-b')).toHaveText('1,500.00');
  await expect(rows.nth(1).locator('.dc-b')).toHaveText('1,300.00');
  await expect(rows.nth(0).locator('.dc-src')).toHaveText('فاتورة');
  await expect(rows.nth(1).locator('.dc-src')).toHaveText('يدوي');
  await expect(page.locator('#dcKpis .io').first()).toContainText('500.00');
  await expect(page.locator('#dcFoot')).toContainText('1,300.00');
  await page.locator('#dcDirSeg button', { hasText: 'صادر' }).click();
  await expect(rows.nth(0)).toBeHidden();
  await expect(rows.nth(1)).toBeVisible();
  await page.locator('#dcDirSeg button', { hasText: 'الكل' }).click();
  await page.fill('#dcFilterQ', 'لا شيء هنا');
  await expect(page.locator('#dcNoMatch')).not.toHaveClass(/\bhidden\b/);
});

test('phone: rows are cards, newest on top, no sideways scroll', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 800 });
  await install(page, { db: db() });
  await page.goto('/daily-cashbox-ar.html');
  await expect(page.locator('#cashbox-table thead')).toBeHidden();
  const a = await page.locator('[data-entry="a"]').boundingBox(), b = await page.locator('[data-entry="b"]').boundingBox();
  expect(b.y).toBeLessThan(a.y);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
