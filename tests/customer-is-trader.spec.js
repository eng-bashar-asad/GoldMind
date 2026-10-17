// A name that is already a trader is not added again as a customer.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('adding a customer with a trader\'s name points to the trader account', async ({ page }) => {
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [], traders: [{ id: 't1', store_id: STORE, name: 'حمدي الخياط' }],
  } });
  await page.goto('/customer-add-ar.html');
  await page.fill('#customer-name', 'حمدي الخياط');
  await page.check('#kyc-declaration');
  await page.click('#save-btn');
  await expect(page.locator('#save-message')).toContainText('مسجّل كتاجر');
  await expect(page.locator('#save-message a[href="ledger-ar.html?trader=t1"]')).toBeVisible();
  expect(calls.some(c => c.method === 'POST' && c.name === 'customers')).toBe(false);
});
