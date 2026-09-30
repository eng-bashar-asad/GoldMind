// "الزبائن" in the side menu: retail customers list, search by name or phone, edit button.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('customers page: retail list, search, edit, menu entry', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [
      { id: 'c1', store_id: STORE, name: 'ريما شالاتي', phone: '0944123456', is_company: false },
      { id: 'c2', store_id: STORE, name: 'هلا الهفل', phone: '0955000111', is_company: false },
      { id: 'c3', store_id: STORE, name: 'شركة النور', phone: '', is_company: true } ],
    customer_debts: [{ store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', cash_amount: 500 }],
  } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/customers-ar.html');
  await expect(page.locator('#count')).toHaveText('2 زبون');           // retail only by default
  await expect(page.locator('#list')).toContainText('عليه 500.00 $');
  await page.fill('#q', '0955');
  await expect(page.locator('#count')).toHaveText('1 زبون');
  await expect(page.locator('#list a:has-text("تعديل")')).toHaveAttribute('href', 'customer-edit-ar.html?id=c2');
  await page.fill('#q', '');
  await page.click('.kind[data-k="company"]');
  await expect(page.locator('#list')).toContainText('شركة النور');
  await page.waitForSelector('#gmNav a[href="customers-ar.html"]', { state: 'attached' });
  expect(await page.locator('#gmNav a[href="customers-ar.html"]').textContent()).toContain('الزبائن');
  expect(errs).toEqual([]);
});
