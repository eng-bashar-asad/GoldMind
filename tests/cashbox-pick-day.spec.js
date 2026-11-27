// Daily cash box: tapping the date opens a calendar and jumps straight to the chosen day.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('pick a day from the date on the day bar', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    daily_cash_log: [
      { id: 'a', store_id: STORE, direction: 'in', amount: 500, currency: 'AED', operation_type: 'بيع قديم', created_at: '2026-03-15T08:00:00Z' },
      { id: 'b', store_id: STORE, direction: 'in', amount: 70, currency: 'AED', operation_type: 'بيع آخر', created_at: '2026-03-16T08:00:00Z' },
    ],
  } });
  await page.goto('/daily-cashbox-ar.html');
  await expect(page.locator('#day-nav-label')).toHaveText('اليوم');
  const pick = page.locator('#day-nav-pick');
  // the invisible date box covers the whole date button, so a tap anywhere on it opens the calendar
  const hit = await page.evaluate(() => {
    document.querySelector('.dc-pick').scrollIntoView({ block: 'center' });
    const r = document.querySelector('.dc-pick').getBoundingClientRect();
    const el = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    return { id: el && el.id, h: document.getElementById('day-nav-pick').getBoundingClientRect().height };
  });
  expect(hit.id).toBe('day-nav-pick');
  expect(hit.h).toBeGreaterThan(10);
  await expect(pick).toHaveAttribute('max', /^\d{4}-\d{2}-\d{2}$/);
  await page.waitForFunction(() => typeof allEntries !== 'undefined' && allEntries.length > 0);
  await pick.fill('2026-03-15');
  await expect(page.locator('#day-nav-label')).toContainText('15/03/2026');
  await expect(page.locator('#entries-heading')).toContainText('15/03/2026');
  await expect(page.locator('body')).toContainText('بيع قديم');
  // a future day is refused: stays on the chosen day
  await pick.fill('2099-01-01');
  await expect(page.locator('#day-nav-label')).toContainText('15/03/2026');
});
