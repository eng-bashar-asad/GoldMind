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
