// The daily cash box must read every movement, not only the first 1000 (the server's page size).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('daily cash box loads more than 1000 movements, newest included', async ({ page }) => {
  const rows = Array.from({ length: 1005 }, (_, i) => ({
    id: 'c' + String(i).padStart(4, '0'), store_id: STORE, direction: 'out', amount: 1, currency: 'AED',
    operation_type: 'مصروف ' + i, created_at: new Date(Date.UTC(2026, 0, 1) + i * 60000).toISOString(),
  }));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    daily_cash_log: rows,
  } });
  await page.goto('/daily-cashbox-ar.html');
  await page.waitForFunction(() => typeof allEntries !== 'undefined' && allEntries.length > 0);
  const ids = await page.evaluate(() => allEntries.map(e => e.id));
  expect(ids.length).toBe(1005);
  expect(ids).toContain('c1004');
});
