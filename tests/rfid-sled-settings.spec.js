// Devices page: Zebra RFD40 Bluetooth sled — status/test/settings card; settings kept on the phone and used by GMUhf.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('RFD40 option shows the in-app card, settings are saved and used for writing and counting', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    zebra_label_fields: [], pieces: [],
  } });
  await page.goto('/devices-setup-ar.html');
  await page.click('[data-kind="rfid"]');
  await page.click('[data-reader="sled"]');
  await expect(page.locator('#reader-sled')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#reader-native')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#nat-web')).not.toHaveClass(/\bhidden\b/); // browser: works only inside the Android app
  await page.locator('#set-write').fill('8');
  await page.locator('#set-count').fill('20');
  await page.click('[data-trigger="toggle"]');
  const s = await page.evaluate(() => GMUhf.settings());
  expect(s).toEqual({ writePower: 8, countPower: 20, trigger: 'toggle' });
  await expect(page.locator('#set-count-v')).toHaveText('20 dBm');
  await page.click('#set-reset');
  expect(await page.evaluate(() => GMUhf.settings())).toEqual({ writePower: 5, countPower: 0, trigger: 'hold' });
  await expect(page.locator('#set-count-v')).toHaveText('أعلى قوة');
});
