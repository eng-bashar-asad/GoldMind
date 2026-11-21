// «الزجاجي الغامق»: listed with the themes, reuses the dark (black-marble) page rules and adds its own glass layer.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('glass theme applies the dark base and frosted cards', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('goldmind_theme', 'glass-dark'));
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'x', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.goto('/theme-picker-ar.html');
  await expect(page.locator('#themes-grid')).toContainText('الزجاجي الغامق');
  const html = page.locator('html');
  await expect(html).toHaveAttribute('data-gm-theme', 'black-marble');
  await expect(html).toHaveAttribute('data-gm-variant', 'glass-dark');
  expect(await page.evaluate(() => getComputedStyle(document.body).backgroundImage)).toContain('radial-gradient');
  // switching away clears the variant
  await page.evaluate(() => goldmindApplyTheme('beige-marble'));
  await expect(html).not.toHaveAttribute('data-gm-variant', /./);
});
