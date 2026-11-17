const { test, expect } = require('@playwright/test');
const { install, USER } = require('./fake-backend');
// Theme / side menu / quick access follow the account (user_profiles.home_prefs), so the Windows
// app — which forgets local storage when it closes — and other devices show the same.
test('account preferences are applied on a fresh device, and a change is saved back', async ({ page }) => {
  const calls = await install(page, { generic: true, db: { user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01T00:00:00Z',
    home_prefs: { theme: 'black-marble', nav_favs: ['ledger-ar.html'], mquick: ['a', 'b'] } }] } });
  await page.goto('/customers-ar.html');
  await expect(page.locator('html')).toHaveAttribute('data-gm-theme', 'black-marble');
  expect(await page.evaluate(() => localStorage.getItem('gm_nav_favs'))).toBe('["ledger-ar.html"]');
  expect(await page.evaluate(() => localStorage.getItem('goldmind_mobile_quick_actions_v4_default'))).toBe('["a","b"]');

  await page.goto('/theme-picker-ar.html');
  await page.evaluate(() => selectTheme('warm-ingot'));
  await expect.poll(() => calls.filter(c => c.name === 'gm_merge_home_prefs').map(c => JSON.parse(c.body).p.theme)).toContain('warm-ingot');
});

test('preferences the account does not have yet are sent up from this device', async ({ page }) => {
  const calls = await install(page, { generic: true, db: { user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01T00:00:00Z', home_prefs: null }] } });
  await page.addInitScript(() => { if (!sessionStorage.getItem('x')) { localStorage.setItem('gm_nav_mini', '1'); sessionStorage.setItem('x', '1'); } });
  await page.goto('/customers-ar.html');
  await expect.poll(() => calls.filter(c => c.name === 'gm_merge_home_prefs').map(c => JSON.parse(c.body).p.nav_mini)).toContain('1');
});
