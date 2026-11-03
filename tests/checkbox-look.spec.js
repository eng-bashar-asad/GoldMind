// Checkboxes: empty = light box with a frame only; ticked = the whole box solid black (no box inside the box).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('checkbox is a plain frame when empty and solid black when ticked', async ({ page }) => {
  await install(page, { realCdn: true, db: { stores: [{ id: STORE, name: 'محل', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.goto('/customer-add-ar.html');
  const cb = page.locator('input[type=checkbox]').first();
  await expect(cb).toBeAttached();
  const look = () => cb.evaluate(el => { const s = getComputedStyle(el); return [s.appearance, s.backgroundColor, s.backgroundImage]; });
  await cb.evaluate(el => { el.checked = false; });
  await expect.poll(look).toEqual(['none', 'rgb(255, 255, 255)', 'none']);
  await cb.evaluate(el => { el.checked = true; });
  await expect.poll(look).toEqual(['none', 'rgb(0, 0, 0)', 'none']); // after the short colour fade
});
