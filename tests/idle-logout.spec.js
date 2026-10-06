// 5 minutes without using the app → this device is signed out (local scope only).
const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

test('idle for more than 5 minutes signs out this device', async ({ page }) => {
  const calls = await install(page, { generic: true, db: {} });
  await page.addInitScript(() => localStorage.setItem('goldmind_last_activity', String(Date.now() - 6 * 60 * 1000)));
  await page.goto('/customers-ar.html');
  await page.waitForURL(/login-entry-ar\.html\?idle=1/);
  const out = calls.find(c => c.kind === 'auth/v1' && c.name === 'logout');
  expect(out && out.url).toContain('scope=local');
  await expect(page.locator('#idleNotice')).toContainText('5 دقائق');
});

test('active within 5 minutes stays signed in', async ({ page }) => {
  await install(page, { generic: true, db: {} });
  await page.addInitScript(() => localStorage.setItem('goldmind_last_activity', String(Date.now() - 3 * 60 * 1000)));
  await page.goto('/customers-ar.html');
  await page.waitForTimeout(1500);
  expect(page.url()).toContain('customers-ar.html');
});
