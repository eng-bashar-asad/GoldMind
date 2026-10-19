// Phone gestures: swipe in from the right edge goes back; pulling down at the top refreshes.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
});
// synthetic finger moves (the page listens to touch events)
const swipe = (page, from, to) => page.evaluate(([f, t]) => {
  const mk = (x, y) => new Touch({ identifier: 1, target: document.body, clientX: x, clientY: y });
  document.body.dispatchEvent(new TouchEvent('touchstart', { touches: [mk(f[0], f[1])], bubbles: true }));
  for (let i = 1; i <= 6; i++) document.body.dispatchEvent(new TouchEvent('touchmove', { touches: [mk(f[0] + (t[0] - f[0]) * i / 6, f[1] + (t[1] - f[1]) * i / 6)], bubbles: true }));
  document.body.dispatchEvent(new TouchEvent('touchend', { touches: [], bubbles: true }));
}, [from, to]);

test.use({ hasTouch: true });

test('swipe from the right edge goes back', async ({ page }) => {
  await install(page, { db: db() });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/customers-ar.html');
  await page.waitForFunction(() => !!window.gmNotify);
  await swipe(page, [386, 400], [250, 405]);
  await page.waitForURL(/index-ar\.html/);
});

test('a short edge swipe does nothing', async ({ page }) => {
  await install(page, { db: db() });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/customers-ar.html');
  await page.waitForFunction(() => !!window.gmNotify);
  await swipe(page, [386, 400], [350, 400]);
  await page.waitForTimeout(400);
  await expect(page).toHaveURL(/customers-ar\.html/);
});

test('pull down at the top reloads a list page', async ({ page }) => {
  await install(page, { db: db() });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/customers-ar.html');
  await page.waitForFunction(() => !!window.gmNotify);
  await page.evaluate(() => { window.__marker = 1; });
  await swipe(page, [200, 150], [200, 400]);
  await page.waitForFunction(() => window.__marker === undefined, null, { timeout: 5000 });
});
