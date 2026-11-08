// On a computer the chip button shows and explains that programming is done from the phone app.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('laptop: «برمجة الشريحة» explains the phone app', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED', rfid_enabled: true }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000123', status: 'available', karat: 18, weight_grams: 5 }],
  } });
  await page.goto('/piece-edit-ar.html?id=p1');
  const btn = page.locator('#gmRfidBtn');
  await expect(btn).toBeVisible();
  await expect(page.locator('#gmRechipBtn')).toBeHidden();
  await btn.click();
  await expect(page.getByText('تطبيق GoldMind على الموبايل', { exact: false })).toBeVisible();
});
