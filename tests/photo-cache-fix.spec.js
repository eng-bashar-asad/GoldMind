// Company settings › القطع والأسعار: old piece photos are re-saved unchanged with a one-year cache.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('re-saves only old photos, byte-for-byte, with the long cache', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: { edit_settings: true } }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  const puts = [];
  await page.route(/\/storage\/v1\/object\//, async r => {
    const u = r.request().url(), m = r.request().method();
    if (/\/object\/list\/piece-photos/.test(u)) return r.fulfill({ json: [
      { id: '1', name: 'old.jpg', metadata: { cacheControl: 'max-age=3600', mimetype: 'image/jpeg' } },
      { id: '2', name: 'new.jpg', metadata: { cacheControl: 'max-age=31536000', mimetype: 'image/jpeg' } },
      { id: null, name: 'sub' }] });
    if (m === 'GET') return r.fulfill({ body: Buffer.from('JPEGBYTES-old'), contentType: 'image/jpeg' });
    if (m === 'PUT') { const b = r.request().postDataBuffer().toString('latin1'); puts.push({ u, b }); return r.fulfill({ json: { Key: 'x' } }); }
    return r.fulfill({ json: {} });
  });
  await page.goto('/company-settings-ar.html');
  await page.locator('.cf-tabs button[data-k="pieces"]').click();
  await page.locator('#photo-cache-btn').click();
  await expect(page.locator('#photo-cache-msg')).toContainText('تمّ تحديث 1 صورة');
  expect(puts).toHaveLength(1);
  expect(puts[0].u).toContain(STORE + '/old.jpg');
  expect(puts[0].b).toContain('JPEGBYTES-old');
  expect(puts[0].b).toMatch(/31536000/);
});
