// «الملكي» theme (بشار 2026-11-12): walnut canvas with gold grain, beige boxes framed in navy, navy top bar.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('royal theme: picker offers it; pages get the walnut canvas, navy bar and framed beige boxes', async ({ page }) => {
  await install(page, { generic: true, realCdn: true, db: { stores: [{ id: STORE, name: 'محل', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], traders: [{ id: 't0', store_id: STORE, name: 'هادي' }] } });
  await page.goto('/theme-picker-ar.html');
  await expect(page.locator('body')).toContainText('الملكي');
  await page.evaluate(() => goldmindApplyTheme('royal-walnut'));
  await page.goto('/ledger-ar.html?trader=t0');
  const s = await page.evaluate(() => ({
    body: getComputedStyle(document.body).backgroundImage,
    header: getComputedStyle(document.querySelector('header')).backgroundImage,
    card: getComputedStyle(document.getElementById('trader-detail-card') || document.querySelector('.rounded-xl.bg-surface-container-lowest')).borderTopColor }));
  expect(s.body).toContain('theme-royal-wood.webp');
  expect(s.header).toContain('linear-gradient');
  expect(s.card).toBe('rgb(22, 48, 92)');
});
