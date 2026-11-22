// Day statement: linked entries are the same colored rectangle on both sides, on dark themes too (بشار 2026-11-23).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('dark theme: linked entries get the same colored fill both sides', async ({ page }) => {
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
  const fills = await page.locator('#rowsBody .cb-lk').evaluateAll(els => els.map(el => getComputedStyle(el).backgroundColor));
  expect(fills.length).toBe(2); // g1 in + g1 out; g2 is alone → plain
  expect(fills[0]).toBe(fills[1]);
  expect(fills[0]).not.toBe('rgba(0, 0, 0, 0)');
  await expect(page.locator('#rowsBody')).toContainText('118,700');
  if (process.env.SHOT) await page.screenshot({ path: '/tmp/daily.png', fullPage: false });
  await page.emulateMedia({ media: 'print' });
  await expect(cell).not.toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
});
