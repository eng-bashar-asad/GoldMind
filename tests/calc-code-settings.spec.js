// Company settings › الأمان: «رمز فتح البرنامج» shows only inside the Windows calculator app and
// asks it to open its change-code screen.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = {
  stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: { edit_settings: true } }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
};

test('in a browser the section is not there', async ({ page }) => {
  await install(page, { db });
  await page.goto('/company-settings-ar.html');
  await expect(page.locator('#bio-on-btn')).toHaveCount(1);
  await expect(page.locator('#calc-code-section')).toHaveCount(0);
});

test('in the Windows app the button asks it to change the code', async ({ page }) => {
  await page.addInitScript(() => {
    window.__calls = [];
    window.__TAURI__ = { core: { invoke: async cmd => { window.__calls.push(cmd); if (cmd !== 'change_code') throw new Error('no'); } } };
  });
  await install(page, { db });
  await page.goto('/company-settings-ar.html');
  await page.locator('.cf-tabs button[data-k="security"]').click();
  await page.locator('#calc-code-btn').click();
  await expect.poll(() => page.evaluate(() => window.__calls)).toEqual(['change_code']);
});
