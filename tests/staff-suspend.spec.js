// «إيقاف مؤقت» (بشار 2026-11-18): the manager suspends a staff member (data kept); a suspended
// member who opens the app is signed out with «عفواً، تم إيقاف حسابك من قبل الإدارة».
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('manager can suspend and reactivate a staff member', async ({ page }) => {
  const calls = await install(page, { db: {
    stores: [{ id: STORE }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' },
            { id: 's2', user_id: 'u2', store_id: STORE, role: 'staff', permissions: {}, full_name: 'ربا' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  await page.route(/\/functions\/v1\/staff-email-admin/, r => r.fulfill({ contentType: 'application/json', body: '{"email":null}' }));
  page.on('dialog', d => d.accept());
  await page.goto('/staff-permissions-ar.html');
  await expect.poll(() => page.evaluate(() => (window.allStaffData || allStaffData || []).length)).toBe(2);
  await page.evaluate(() => openStaffDetail('s2'));
  await expect(page.locator('#detailSuspendBtn')).toHaveText('إيقاف مؤقت');
  await page.click('#detailSuspendBtn');
  await expect.poll(() => calls.some(c => c.method === 'PATCH' && /\/staff\?/.test(c.url) && /"suspended_at":"20/.test(c.body || ''))).toBe(true);
  await expect(page.locator('#detailSuspendBtn')).toHaveText('إعادة تفعيل الحساب');
  // the owner's own card has no suspend option
  await page.evaluate(() => openStaffDetail(GOLDMIND_STAFF_ID));
  await expect(page.locator('#detailSuspendBox')).toHaveClass(/\bhidden\b/);
});

test('a suspended staff member is signed out with the message', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'staff', permissions: {}, full_name: 'ربا', suspended_at: '2026-11-18T18:00:00Z' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  await page.goto('/index-ar.html');
  await page.waitForURL(/login-entry-ar\.html\?suspended=1/);
  await expect(page.locator('#suspendedNotice')).toBeVisible();
  await expect(page.locator('#suspendedNotice')).toHaveText('عفواً، تم إيقاف حسابك من قبل الإدارة.');
});
