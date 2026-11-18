// Staff details (بشار 2026-11-18): show the username a staff member signs in with, let the manager change it
// and set a new password; a username-only account's private placeholder email is not shown as a real email.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('staff details: username shown, placeholder email hidden, username and password can be set', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' },
            { id: 's2', user_id: 'u2', store_id: STORE, role: 'staff', permissions: {}, full_name: 'تلفون المحل' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  const sent = [];
  await page.route(/\/functions\/v1\/staff-email-admin/, r => {
    const b = JSON.parse(r.request().postData()); sent.push(b);
    const body = b.action === 'get' ? { email: 'shop_phone.a15f496a@staff.goldmind.app', username: 'shop_phone', placeholder: true }
      : b.action === 'set_username' ? { success: true, username: b.new_username } : { success: true };
    r.fulfill({ contentType: 'application/json', body: JSON.stringify(body) });
  });
  page.on('dialog', d => d.accept());
  await page.goto('/staff-permissions-ar.html');
  await expect(page.locator('text=تلفون المحل').first()).toBeVisible();
  await page.evaluate(() => openStaffDetail('s2'));
  await expect(page.locator('#detailUsername')).toHaveValue('shop_phone');
  await expect(page.locator('#detailEmail')).toHaveValue('');
  await expect(page.locator('#detailEmailLbl')).toHaveText('البريد الإلكتروني (اختياري)');

  await page.fill('#detailUsername', 'shop.damascus');
  await page.click('text=حفظ اسم المستخدم');
  await expect.poll(() => sent.find(b => b.action === 'set_username')).toMatchObject({ staff_id: 's2', new_username: 'shop.damascus' });

  await page.fill('#detailPassword', 'short');
  await page.click('text=تعيين كلمة المرور');
  await expect(page.locator('#detailLoginError')).toContainText('8 خانات');
  await page.fill('#detailPassword', 'Shop2026pass');
  await page.click('text=تعيين كلمة المرور');
  await expect.poll(() => sent.find(b => b.action === 'set_password')).toMatchObject({ staff_id: 's2', new_password: 'Shop2026pass' });
  await expect(page.locator('#detailPassword')).toHaveValue('');
});
