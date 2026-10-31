// The packaged app draws under the status bar (Android 15+, Capacitor 8): the update bar must sit below it
// so «تنزيل» can be tapped.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('update bar stays below the status bar and its download link is tappable', async ({ page }) => {
  await page.addInitScript(() => {
    window.Capacitor = { isNativePlatform: () => true };
  });
  await install(page, { db: { stores: [{ id: STORE, name: 'محل', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.route(/build-info\.json/, r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ sha: 'a'.repeat(40) }) }));
  await page.route(/api\.github\.com\/repos\/.*\/releases\/tags\/app-latest/, r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ body: 'commit ' + 'b'.repeat(40) }) }));
  await page.goto('/reports-ar.html');
  const link = page.locator('#gm-update-banner a', { hasText: 'تنزيل' });
  await expect(link).toBeVisible();
  await page.evaluate(() => document.documentElement.style.setProperty('--safe-area-inset-top', '32px')); // what Capacitor injects
  const box = await link.boundingBox();
  expect(box.y).toBeGreaterThanOrEqual(32);
  expect(await page.evaluate(({ x, y }) => document.elementFromPoint(x, y).textContent, { x: box.x + box.width / 2, y: box.y + box.height / 2 })).toBe('تنزيل');
});
