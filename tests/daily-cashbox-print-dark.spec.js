// Day statement on a dark theme: no pastel patchwork on screen (a thin colored edge marks linked entries); paper keeps the fills.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('dark theme: linked rows get an edge, not a pastel fill', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => localStorage.setItem('goldmind_theme', 'black-marble'));
  const day = new Date(); day.setHours(10, 0, 0, 0);
  const e = (id, dir, amt, op, g) => ({ id, store_id: STORE, direction: dir, amount: amt, currency: 'AED', operation_type: op, link_group: g, created_at: day.toISOString() });
  await install(page, { generic: true, realCdn: !!process.env.SHOT, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    daily_cash_log: [e('a', 'in', 118700, 'مبيعات حجازي سبايك', 'g1'), e('b', 'out', 116195, 'شراء سبايك', 'g1'), e('c', 'in', 11000, 'مبيعات صقر', 'g2'), e('d', 'out', 35, 'اكل مصطفى', null)],
  } });
  await page.goto('/daily-cashbox-print-ar.html');
  const cell = page.locator('#rowsBody .cb-lk').first();
  await expect(cell).toBeVisible();
  await expect(cell).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
  expect(await cell.evaluate(el => getComputedStyle(el).boxShadow)).toContain('inset');
  await expect(page.locator('#rowsBody')).toContainText('118,700');
  // the linked pair g1 carries the same number on both sides; g2 is alone → no number
  await expect(page.locator('#rowsBody .cb-tag')).toHaveCount(2);
  await expect(page.locator('#rowsBody .cb-tag').nth(0)).toContainText('1');
  await expect(page.locator('#rowsBody .cb-tag').nth(1)).toContainText('1');
  if (process.env.SHOT) await page.screenshot({ path: '/tmp/daily.png', fullPage: false });
  await page.emulateMedia({ media: 'print' });
  await expect(cell).not.toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
});
