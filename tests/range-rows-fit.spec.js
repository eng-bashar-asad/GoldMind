// Period statement on a phone: long names and link chips wrap; the amounts stay on the screen.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('period statement rows fit a 375px phone', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 800 });
  const t = '2026-11-25T';
  await install(page, { db: { stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], daily_cash_log: [
      { id: 'a', store_id: STORE, direction: 'out', amount: 10000, currency: 'AED', operation_type: 'وصلو ع حساب المعلم', link_group: 'g1', created_at: t + '15:57:00Z' },
      { id: 'b', store_id: STORE, direction: 'in', amount: 120000, currency: 'AED', operation_type: 'تحويل ع حساب المعلم دفعت من علاء عوا', link_group: 'g1', created_at: t + '15:56:00Z' },
      { id: 'c', store_id: STORE, direction: 'out', amount: 125, currency: 'AED', operation_type: 'بانزين لسيارة مارسيدس والاسكليد المعلم', created_at: t + '15:58:00Z' }] } });
  await page.goto('/daily-cashbox-range-ar.html?from=2026-11-25&to=2026-11-25'); await expect(page.locator('.cr-tbl tbody tr')).toHaveCount(3);
  const r = await page.evaluate(() => [document.documentElement.scrollWidth, innerWidth, [...document.querySelectorAll('.cr-tbl tbody tr')].map(tr => Math.round(tr.getBoundingClientRect().left))]);
  expect(r[0]).toBeLessThanOrEqual(r[1]);
  const amt = await page.evaluate(() => [...document.querySelectorAll('.cr-tbl .c-amt')].map(td => Math.round(td.getBoundingClientRect().left)));
  amt.forEach(x => expect(x).toBeGreaterThanOrEqual(0));
});
