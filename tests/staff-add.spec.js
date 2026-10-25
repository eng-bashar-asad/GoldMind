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

// The person already works in another of the owner's companies: added here with his own account (no new password).
test('existing account the owner manages elsewhere is added with the same login', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  await page.route(/\/functions\/v1\/add-staff-direct/, r => r.fulfill({ json: { success: true, linked: true, username: null, email: 'mhd@example.com' } }));
  await page.goto('/staff-permissions-ar.html');
  await page.click('#direct-add-toggle-btn');
  await page.fill('#direct-name', 'محمد');
  await page.fill('#direct-email', 'mhd@example.com');
  await page.fill('#direct-whatsapp', '963900000000');
  await page.click('#direct-add-btn');
  await expect(page.locator('body')).toContainText('بحسابه الحالي');
  await expect(page.locator('#direct-add-result')).toHaveClass(/\bhidden\b/);
});
