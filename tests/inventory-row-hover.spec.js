// Stock list (بشار 2026-11-16): hovering a piece row keeps the row's own colours (it used to turn
// cream on the dark marble theme and hide the text) and lifts it out instead.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const base = { stores: [{ id: STORE, name: 'محل', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] };
const P = id => ({ id, store_id: STORE, barcode: id, description_ar: 'خاتم', karat: 18, weight_grams: 5, status: 'available', box_name: 'قطع ذهبية', created_at: '2026-11-10T10:00:00Z' });

test('hovered piece row keeps its background and lifts', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.addInitScript(() => localStorage.setItem('goldmind_theme', 'black-marble'));
  await install(page, { generic: true, db: { ...base, pieces: [P('a1'), P('a2')] } });
  await page.goto('/inventory-list-ar.html?box=' + encodeURIComponent('قطع ذهبية') + '&k=18');
  const row = page.locator('tr.gm-lift').first();
  await expect(row).toBeVisible();
  const bg = await row.evaluate(e => getComputedStyle(e).backgroundColor);
  await row.hover(); await page.waitForTimeout(300);
  expect(await row.evaluate(e => getComputedStyle(e).backgroundColor)).toBe(bg);
  expect(await row.evaluate(e => getComputedStyle(e).transform)).not.toBe('none');
});
