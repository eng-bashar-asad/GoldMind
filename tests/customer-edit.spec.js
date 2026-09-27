// Full customer edit: personal data (date of birth etc.) is loaded and saved.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('edit an individual customer: add date of birth and ID', async ({ page }) => {
  const updates = [];
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'B' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'رزان الحلبي', phone: '501234567', phone_country_code: '971', is_company: false, nationality: 'سورية' }],
  } });
  await page.route(/\/rest\/v1\/customers\?.*id=eq\.c1/, (r) => {
    if (r.request().method() === 'PATCH') { updates.push(JSON.parse(r.request().postData())); return r.fulfill({ status: 204, body: '' }); }
    return r.fallback();
  });
  await page.goto('/customer-edit-ar.html?id=c1');
  await expect(page.locator('#f-name')).toHaveValue('رزان الحلبي');
  await expect(page.locator('#f-nationality')).toHaveValue('سورية');
  await expect(page.locator('#f-phone-code')).toHaveValue('971');
  await expect(page.locator('#company-fields')).toHaveClass(/\bhidden\b/);
  await page.locator('#f-dob').pressSequentially('14051990');
  await expect(page.locator('#f-dob')).toHaveValue('14/05/1990');
  await page.selectOption('#f-id-type', 'passport');
  await page.fill('#f-id-number', 'N1234567');
  await page.click('#save-btn');
  await expect(page.locator('#save-message')).toContainText('تم حفظ');
  expect(updates).toHaveLength(1);
  expect(updates[0]).toMatchObject({ date_of_birth: '1990-05-14', id_type: 'passport', id_number: 'N1234567', nationality: 'سورية', phone_country_code: '971' });
  expect(updates[0]).not.toHaveProperty('ubo_name');
});

test('a future date of birth is refused', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'B' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'رزان', is_company: false, id_type: 'residency', id_expiry_date: '2030-03-01' }],
  } });
  await page.goto('/customer-edit-ar.html?id=c1');
  await expect(page.locator('#f-name')).toHaveValue('رزان');
  await expect(page.locator('#f-id-expiry')).toHaveValue('01/03/2030');
  await expect(page.locator('#f-id-type')).toHaveValue('residency'); // old value kept
  await page.fill('#f-id-expiry', '31/02/2030');
  await page.click('#save-btn');
  await expect(page.locator('#save-message')).toContainText('يوم/شهر/سنة');
  await page.fill('#f-id-expiry', '01/03/2030');
  await page.fill('#f-dob', '01/01/2099');
  await page.click('#save-btn');
  await expect(page.locator('#save-message')).toContainText('غير صحيح');
  await expect(page.locator('#save-btn')).toBeEnabled();
});
