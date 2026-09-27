// Adding an employee with just their email (no username) is allowed.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('add employee with email only: username is left to the server', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  let sent = null;
  await page.route(/\/functions\/v1\/add-staff-direct/, r => {
    sent = JSON.parse(r.request().postData());
    return r.fulfill({ json: { success: true, username: 'ahmad', email: sent.email, temp_password: 'Xyz12345' } });
  });
  await page.goto('/staff-permissions-ar.html');
  await page.click('#direct-add-toggle-btn');
  await page.fill('#direct-name', 'أحمد');
  await page.fill('#direct-email', 'ahmad@example.com');
  await page.fill('#direct-whatsapp', '971501234567');
  await page.click('#direct-add-btn');
  await expect(page.locator('#direct-add-result')).toBeVisible();
  expect(sent).toMatchObject({ email: 'ahmad@example.com', full_name: 'أحمد' });
  expect(sent.username).toBeUndefined();
});

test('add employee with neither email nor username asks for one', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  await page.goto('/staff-permissions-ar.html');
  await page.click('#direct-add-toggle-btn');
  await page.fill('#direct-name', 'أحمد');
  await page.fill('#direct-whatsapp', '971501234567');
  await page.click('#direct-add-btn');
  await expect(page.locator('#direct-add-error')).toContainText('البريد');
});
