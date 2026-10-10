const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

test('home page accounting alert also counts warnings (e.g. a payment missing from the daily cash box)', async ({ page }) => {
  await install(page, { generic: true, rpc: { accounting_health_check: () => ({ body: [{ severity: 'warning', code: 'daily_box_missing', title: 't', details: 'd' }] }) } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/index-ar.html');
  await expect(page.locator('a[role="alert"][href="accounting-check-ar.html"]').first()).toContainText('1 تنبيه');
});
