// Editing a cancelled piece (e.g. its weight) must not blank its status.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('saving a cancelled piece keeps «ملغاة»', async ({ page }) => {
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '001051', status: 'cancelled', weight_grams: 28, karat: 18, piece_type: 'خاتم', description_ar: 'قطع كسر' }],
  } });
  await page.goto('/piece-edit-ar.html?id=p1');
  await expect(page.locator('#status')).toHaveValue('cancelled');
  await page.evaluate(() => { document.getElementById('gmEditBox').open = true; });
  await page.locator('#save-btn').click();
  await expect.poll(() => calls.filter(c => c.method === 'PATCH' && /\/pieces/.test(c.url)).length).toBeGreaterThan(0);
  const body = JSON.parse(calls.filter(c => c.method === 'PATCH' && /\/pieces/.test(c.url))[0].body);
  expect(body.status).toBe('cancelled');
});
