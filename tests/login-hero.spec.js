const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');
// Both sign-in screens show the same animated GoldMind artwork (gm-hero.js), not the old shield logo.
for (const [f, pre] of [['login-entry-ar.html', null], ['login-ar-4.html', 'eng@example.com']]) test('hero on ' + f, async ({ page }) => {
  await install(page, { anon: true, db: {} });
  if (pre) await page.addInitScript(e => sessionStorage.setItem('goldmind_email', e), pre);
  await page.goto('/' + f);
  await expect(page.locator('.gm-hero img[src="goldmind-hero.jpg"]')).toHaveCount(1);
  await expect(page.locator('.gm-hero-sparks i').first()).toBeAttached();
  // sharper artwork: the screen picks the size it needs, up to 2048px (بشار 2026-11-27)
  await expect(page.locator('.gm-hero img')).toHaveAttribute('srcset', /goldmind-hero-2048\.jpg 2048w/);
  await expect(page.locator('img[src*="logo-transparent"]')).toHaveCount(0);
});
