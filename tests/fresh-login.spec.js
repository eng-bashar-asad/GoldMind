// A login left in the browser from days ago must not skip the emailed code,
// and typing on the login screen must not count as activity.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = { stores: [{ id: STORE, name: 'محل' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] };

test('old saved login: email login asks for the code instead of opening the last company', async ({ page }) => {
  const calls = await install(page, { db });
  await page.goto('/login-entry-ar.html');
  await page.evaluate(() => localStorage.setItem('goldmind_last_activity', String(Date.now() - 2 * 86400e3)));
  await page.locator('body').click();
  await page.keyboard.press('a');
  expect(Number(await page.evaluate(() => localStorage.getItem('goldmind_last_activity')))).toBeLessThan(Date.now() - 86400e3);
  await page.evaluate(() => goToStep('join'));
  await page.fill('#joinEmail', 't@example.com');
  await page.click('#joinSubmitBtn');
  await page.waitForURL(/login-ar-4\.html/);
  await page.waitForTimeout(1200);
  expect(page.url()).toContain('login-ar-4.html');             // stays on the code screen
  expect(calls.some(c => c.kind === 'auth/v1' && c.name === 'logout')).toBe(true);
});
