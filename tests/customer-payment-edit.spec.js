// Customer page: a payment from the customer can be edited (amount/notes) or deleted.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-10-05T10:00:00Z';

test('edit and delete a customer payment', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const calls = await install(page, { generic: true, rpc: { customer_payment_update: () => ({ body: { ok: true } }) }, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ديمة الانصاري' }], invoices: [],
    customer_debts: [{ id: 'p1', store_id: STORE, customer_id: 'c1', movement_type: 'debt_decrease', source: 'payment', cash_amount: 19780, notes: 'بالليرة', created_at: T }]
  } });
  await page.goto('/customer-debts-ar.html?open=c1');
  await page.click('button:has-text("تعديل الدفعة")');
  await page.fill('#pay-edit-amount-p1', '19000');
  await page.fill('#pay-edit-notes-p1', 'تعديل');
  await page.locator('#pay-edit-p1 button', { hasText: 'حفظ التعديل' }).click();
  await expect.poll(() => calls.filter(c => c.name === 'customer_payment_update').length).toBe(1);
  expect(JSON.parse(calls.find(c => c.name === 'customer_payment_update').body)).toEqual({ p_id: 'p1', p_amount: 19000, p_notes: 'تعديل' });
  page.on('dialog', d => d.accept());
  await page.click('button:has-text("حذف الدفعة")');
  await expect.poll(() => calls.filter(c => c.name === 'customer_payment_update').length).toBe(2);
  expect(JSON.parse(calls.filter(c => c.name === 'customer_payment_update')[1].body)).toMatchObject({ p_id: 'p1', p_amount: 0 });
  expect(errs.filter(e => !e.includes("reading 'replace'"))).toEqual([]);
});

test('edit a cash-out to the customer', async ({ page }) => {
  const calls = await install(page, { generic: true, rpc: { customer_payment_update: () => ({ body: { ok: true } }) }, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ديمة الانصاري' }], invoices: [],
    customer_debts: [{ id: 'o1', store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', source: 'cash_out', cash_amount: 500, notes: 'صرف للعميل', created_at: T }]
  } });
  await page.goto('/customer-debts-ar.html?open=c1');
  await page.click('button:has-text("تعديل الصرف")');
  await page.fill('#pay-edit-amount-o1', '450');
  await page.locator('#pay-edit-o1 button', { hasText: 'حفظ التعديل' }).click();
  await expect.poll(() => calls.filter(c => c.name === 'customer_payment_update').length).toBe(1);
  expect(JSON.parse(calls.find(c => c.name === 'customer_payment_update').body)).toMatchObject({ p_id: 'o1', p_amount: 450 });
  await expect(page.locator('button:has-text("حذف الصرف")')).toBeVisible();
});

test('an invoice moved to another customer disappears from the old one', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ديمة الانصاري' }, { id: 'c2', store_id: STORE, name: 'بيت دولة' }],
    invoices: [{ id: 'i17', store_id: STORE, customer_id: 'c2', invoice_number: 'INV-17', type: 'sale', status: 'unpaid', total_amount: 11900, amount_paid: 11700, created_at: T }],
    customer_debts: [
      { id: 'a', store_id: STORE, customer_id: 'c1', invoice_id: 'i17', movement_type: 'debt_increase', source: null, cash_amount: 200, notes: 'متبقي فاتورة بيع INV-17', created_at: T, invoice: { invoice_number: 'INV-17' } },
      { id: 'b', store_id: STORE, customer_id: 'c1', invoice_id: 'i17', movement_type: 'debt_decrease', source: 'invoice_edit', cash_amount: 200, notes: 'نقل دين الفاتورة INV-17', created_at: T, invoice: { invoice_number: 'INV-17' } },
      { id: 'p', store_id: STORE, customer_id: 'c1', movement_type: 'debt_decrease', source: 'payment', cash_amount: 100, notes: 'دفعة', created_at: T }]
  } });
  await page.goto('/customer-debts-ar.html?open=c1');
  await expect(page.locator('#movements-list')).toContainText('دفعة');
  await expect(page.locator('#movements-list')).not.toContainText('INV-17');
});
