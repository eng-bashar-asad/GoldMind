// Editing a sale invoice can move it to another customer (server moves the remaining debt).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('sale invoice edit: change the customer', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  let moved = null;
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [{ id: 's1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'unpaid', payment_method: 'credit', customer_id: 'c1', total_amount: 1000, amount_paid: 0, created_at: '2026-10-01T07:00:00Z' }],
    invoice_items: [{ id: 'it1', invoice_id: 's1', karat: 21, weight_grams: 5, line_total: 1000, description: 'خاتم' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'أحمد', phone: '0501' }, { id: 'c2', store_id: STORE, name: 'أحمد سالم', phone: '0502' }],
    pieces: []
  }, rpc: { sale_invoice_change_customer: a => { moved = a; return { body: null }; } } });
  await page.goto('/invoice-edit-ar.html?id=s1');
  await expect(page.locator('#customerCurrent')).toContainText('أحمد');
  await page.fill('#customerSearch', 'أحمد');
  await page.locator('#customerResults button').first().click();     // only c2: the current one is hidden
  await expect(page.locator('#customerResults')).toContainText('أحمد سالم');
  page.on('dialog', d => d.accept());
  await page.click('#save-btn');
  await expect.poll(() => moved).toEqual({ p_invoice: 's1', p_customer: 'c2' });
  await expect.poll(() => calls.some(c => c.method === 'PATCH' && c.name === 'invoices')).toBe(true);
  expect(errs).toEqual([]);
});

test('sale invoice edit: mixed payment (cash + card, rest on debt)', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [{ id: 's1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', payment_method: 'cash', customer_id: 'c1', total_amount: 2350, amount_paid: 2350, created_at: '2026-10-01T07:00:00Z' }],
    invoice_items: [{ id: 'it1', invoice_id: 's1', karat: 18, weight_grams: 17.55, line_total: 2350, description: 'إسوارة' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'محمد', phone: '1' }], pieces: []
  } });
  await page.goto('/invoice-edit-ar.html?id=s1');
  await expect(page.locator('#lockedNumber')).toHaveText('INV-1');
  await page.selectOption('#paymentMethodSelect', 'mixed');
  await page.fill('#mixedCash', '1000');
  await page.fill('#mixedBank', '1000');
  await expect(page.locator('#mixedNote')).toContainText('350');
  page.on('dialog', d => d.accept());
  await page.click('#save-btn');
  await expect.poll(() => calls.some(c => c.method === 'PATCH' && c.name === 'invoices')).toBe(true);
  const body = JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'invoices').body);
  expect([body.payment_method, body.amount_paid, body.cash_paid_amount, body.bank_paid_amount, body.status]).toEqual(['mixed', 2000, 1000, 1000, 'unpaid']);
  await expect.poll(() => calls.filter(c => c.method === 'POST' && c.name === 'customer_debts').length).toBe(1);
  expect(JSON.parse(calls.find(c => c.method === 'POST' && c.name === 'customer_debts').body).cash_amount).toBe(350);
  expect(errs).toEqual([]);
});
