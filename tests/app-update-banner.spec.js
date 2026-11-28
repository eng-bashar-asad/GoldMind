// The packaged app draws under the status bar (Android 15+, Capacitor 8): the update bar must sit below it
// so «تنزيل» can be tapped.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

// Fake GMUpdate plugin (APKs from 2026-11-28): records the address and plays a download.
const FAKE_PLUGIN = () => {
  window.__installs = [];
  let cb = null;
  window.Capacitor = { isNativePlatform: () => true, Plugins: { GMUpdate: {
    addListener: (ev, f) => { cb = f; return Promise.resolve({ remove() {} }); },
    install: ({ url }) => { window.__installs.push(url); cb && cb({ percent: 50 }); cb && cb({ percent: 100 }); return Promise.resolve(); },
  } } };
};
const DB = { stores: [{ id: STORE, name: 'محل', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] };
const routes = async (page, release) => {
  await page.route(/build-info\.json/, r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ sha: 'a'.repeat(40), content: '1234567890abcdef', built_at: '2026-11-20T23:00:00Z' }) }));
  await page.route(/api\.github\.com\/repos\/.*\/releases\/tags\/app-latest/, r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ body: release }) }));
};

test('update bar stays below the status bar; «تنزيل» installs from inside the app', async ({ page }) => {
  await page.addInitScript(FAKE_PLUGIN);
  await install(page, { db: DB });
  await routes(page, 'commit ' + 'b'.repeat(40));
  await page.goto('/reports-ar.html');
  const go = page.locator('#gm-update-go');
  await expect(go).toBeVisible();
  await page.evaluate(() => document.documentElement.style.setProperty('--safe-area-inset-top', '32px')); // what Capacitor injects
  const box = await go.boundingBox();
  expect(box.y).toBeGreaterThanOrEqual(32);
  expect(await page.evaluate(({ x, y }) => document.elementFromPoint(x, y).id, { x: box.x + box.width / 2, y: box.y + box.height / 2 })).toBe('gm-update-go');
  await go.click();
  await expect(page.locator('#gm-update-text')).toContainText('تثبيت');
  expect(await page.evaluate(() => window.__installs)).toEqual([expect.stringMatching(/releases\/download\/app-latest\/GoldMind\.apk\?v=bbbbbbbbbbbb$/)]); // per-version address
});

test('an older APK without the plugin opens the download link', async ({ page }) => {
  await page.addInitScript(() => { window.Capacitor = { isNativePlatform: () => true }; });
  await install(page, { db: DB });
  await routes(page, 'commit ' + 'b'.repeat(40));
  await page.route(/GoldMind\.apk/, r => r.fulfill({ body: 'apk' }));
  await page.goto('/reports-ar.html');
  const nav = page.waitForRequest(/GoldMind\.apk\?v=bbbbbbbbbbbb/);
  await page.locator('#gm-update-go').click();
  await nav;
});

// Settings › التطبيق › «تنزيل آخر إصدار» (بشار 2026-11-28)
for (const [label, rel, state, btn] of [
  ['newer version', 'commit ' + 'b'.repeat(40) + ' (content fedcba0987654321)', 'يتوفر إصدار جديد', 'تنزيل آخر إصدار وتثبيته'],
  ['up to date', 'commit ' + 'a'.repeat(40) + ' (content 1234567890abcdef)', 'لديك آخر إصدار', 'إعادة تنزيل آخر إصدار']]) {
  test('settings shows the app version and installs the latest — ' + label, async ({ page }) => {
    await page.addInitScript(FAKE_PLUGIN);
    await install(page, { db: DB });
    await routes(page, rel);
    await page.goto('/settings-ar.html');
    await expect(page.locator('#appUpdateSection')).toBeVisible();
    await expect(page.locator('#appUpdateState')).toContainText(state);
    await expect(page.locator('#appUpdateState')).toContainText('2026');
    await expect(page.locator('#appUpdateBtn')).toHaveText(btn);
    await page.locator('#appUpdateBtn').click();
    await expect(page.locator('#appUpdateState')).toContainText('تثبيت');
    expect(await page.evaluate(() => window.__installs.length)).toBe(1);
  });
}

test('settings: no app section on the website', async ({ page }) => {
  await install(page, { db: DB });
  await page.goto('/settings-ar.html');
  await expect(page.locator('#appUpdateSection')).toHaveClass(/\bhidden\b/);
});

// A new commit that changes nothing in the app (tests, SQL, notes) is not an update (Bashar 2026-11-02).
for (const [label, releaseContent, shown] of [['same app files: no bar', '1234567890abcdef', false], ['changed app files: bar', 'fedcba0987654321', true]]) {
  test('update bar compares app content — ' + label, async ({ page }) => {
    await page.addInitScript(() => { window.Capacitor = { isNativePlatform: () => true }; });
    await install(page, { db: { stores: [{ id: STORE, name: 'محل', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
    await page.route(/build-info\.json/, r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ sha: 'a'.repeat(40), content: '1234567890abcdef' }) }));
    await page.route(/api\.github\.com\/repos\/.*\/releases\/tags\/app-latest/, r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ body: 'Automatically built from commit ' + 'b'.repeat(40) + ' (content ' + releaseContent + '). Download' }) }));
    const seen = page.waitForResponse(/releases\/tags\/app-latest/);
    await page.goto('/reports-ar.html');
    await seen;
    if (shown) await expect(page.locator('#gm-update-banner')).toBeVisible();
    else { await page.waitForTimeout(500); await expect(page.locator('#gm-update-banner')).toHaveCount(0); }
  });
}

test('installed app keeps the page below the status bar (no viewport-fit=cover); the website still uses it', async ({ page }) => {
  await page.addInitScript(() => { window.Capacitor = { isNativePlatform: () => true }; });
  await page.goto('/reports-ar.html');
  expect(await page.locator('meta[name=viewport]').getAttribute('content')).not.toContain('viewport-fit=cover');
});
test('website keeps viewport-fit=cover', async ({ page }) => {
  await page.goto('/reports-ar.html');
  expect(await page.locator('meta[name=viewport]').getAttribute('content')).toContain('viewport-fit=cover');
});
