// Editing a posted sale invoice on the sale screen (new-sale-ar.html?edit=<id>),
// saved by the shared gm-invoice-edit.js, plus the customer's deposit credit note.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const base = (inv, extra = {}) => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  // the fake backend has no embedding: the invoice row carries its items and customer
  invoices: [{ store_id: STORE, invoice_number: 'INV-40', type: 'sale', customer_id: 'c1', created_at: '2026-10-11T07:00:00Z',
    customer: { id: 'c1', name: 'رجاء', phone: '050' }, ...inv }],
  customers: [{ id: 'c1', store_id: STORE, name: 'رجاء', phone: '050' }],
  customer_debts: [], gold_prices: [], gold_stock_lots: [], pieces: [], ...extra
});
const posts = (calls, name) => calls.filter(c => c.method === 'POST' && c.name === name).map(c => JSON.parse(c.body));
const patches = (calls, name) => calls.filter(c => c.method === 'PATCH' && c.name === name).map(c => JSON.parse(c.body));

async function openEdit(page, id) {
  page.on('dialog', d => d.accept().catch(() => {}));
  await page.goto('/new-sale-ar.html?edit=' + id);
  await expect(page.locator('#edit-banner')).toContainText('INV-40');
}
async function setPrice(page, row, v) {
  await page.locator('#cart-body tr').nth(row).locator('button[onclick^="editCartPrice"]').click();
  const inp = page.locator('#cart-body input[type=number]');
  await inp.fill(String(v)); await inp.press('Enter');
}

test('paid invoice: change a price → one cash difference row, invoice total updated', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const calls = await install(page, { db: base({ id: 's1', status: 'paid', payment_method: 'cash', total_amount: 6100, amount_paid: 6100,
    items: [{ id: 'l1', invoice_id: 's1', piece_id: 'p1', barcode: '000856', karat: 18, weight_grams: 11.77, line_total: 4900, description: 'خاتم' },
            { id: 'l2', invoice_id: 's1', karat: 18, weight_grams: 8, line_total: 1200, description: 'حلق' }] }) });
  await openEdit(page, 's1');
  await expect(page.locator('#sale-title')).toHaveText('تعديل فاتورة');
  await expect(page.locator('#cart-body tr')).toHaveCount(2);
  await setPrice(page, 0, 5170);
  await page.click('#save-invoice-btn');
  await expect.poll(() => patches(calls, 'invoices').length).toBe(1);
  expect(patches(calls, 'invoices')[0]).toMatchObject({ total_amount: 6370, amount_paid: 6370, status: 'paid' });
  await expect.poll(() => posts(calls, 'cash_movements').length).toBe(1);
  expect(posts(calls, 'cash_movements')[0]).toMatchObject({ direction: 'in', amount: 270, edit_delta: true });
  expect(patches(calls, 'invoice_items').length).toBe(2);
  expect(errs).toEqual([]);
});

test('remove a piece → back in stock; add a typed line → new invoice line', async ({ page }) => {
  const calls = await install(page, { db: base({ id: 's2', status: 'paid', payment_method: 'cash', total_amount: 6100, amount_paid: 6100,
    items: [{ id: 'l1', invoice_id: 's2', piece_id: 'p1', barcode: '000856', karat: 18, weight_grams: 11.77, line_total: 4900, description: 'خاتم' },
            { id: 'l2', invoice_id: 's2', karat: 18, weight_grams: 8, line_total: 1200, description: 'حلق' }] },
    { gold_stock_lots: [{ id: 'lot1', store_id: STORE, karat: 18, box_name: null, weight_grams_total: 50, weight_grams_remaining: 50, cost_fabrication_per_gram: 0, created_at: '2026-01-01T00:00:00Z' }] }) });
  await openEdit(page, 's2');
  await page.locator('#cart-body tr').first().locator('button[onclick^="removeFromCart"]').click();
  await page.click('#sale-tabs [data-tab="manual"]');
  await page.fill('#manual-weight', '5');
  await page.fill('#manual-price', '800');
  await page.locator('button[onclick="addManualToCart()"]').click();
  await expect(page.locator('#manual-source')).toHaveClass(/border-error/); // source is required
  await page.selectOption('#manual-source', 'bulk');
  await page.locator('button[onclick="addManualToCart()"]').click();
  await expect(page.locator('#cart-body tr')).toHaveCount(2);
  await page.click('#save-invoice-btn');
  await expect.poll(() => patches(calls, 'invoices').length).toBe(1);
  expect(patches(calls, 'invoices')[0]).toMatchObject({ total_amount: 2000 });
  await expect.poll(() => calls.some(c => c.method === 'DELETE' && c.name === 'invoice_items' && c.url.includes('l1'))).toBe(true);
  await expect.poll(() => patches(calls, 'pieces').some(b => b.status === 'available')).toBe(true);
  expect(posts(calls, 'invoice_items')[0]).toMatchObject({ invoice_id: 's2', line_total: 800, weight_grams: 5 });
  await expect.poll(() => posts(calls, 'cash_movements').length).toBe(1);
  expect(posts(calls, 'cash_movements')[0]).toMatchObject({ direction: 'out', amount: 4100 });
  // the bulk and diamond tabs are not offered while editing
  await expect(page.locator('#sale-tabs [data-tab="stock"]')).toBeHidden();
});

test('half-paid invoice: a higher price goes to the customer\'s debt, not the box', async ({ page }) => {
  const calls = await install(page, { db: base({ id: 's3', status: 'unpaid', payment_method: 'mixed', cash_paid_amount: 500, bank_paid_amount: 0, total_amount: 1000, amount_paid: 500,
    items: [{ id: 'l1', invoice_id: 's3', karat: 21, weight_grams: 5, line_total: 1000, description: 'خاتم' }] }) });
  await openEdit(page, 's3');
  await expect(page.locator('#mixed-cash-amount')).toHaveValue('500');
  await setPrice(page, 0, 1200);
  await expect(page.locator('#mixed-remaining-note')).toContainText('700');
  await page.click('#save-invoice-btn');
  await expect.poll(() => posts(calls, 'customer_debts').length).toBe(1);
  expect(posts(calls, 'customer_debts')[0]).toMatchObject({ movement_type: 'debt_increase', cash_amount: 200, source: 'invoice_edit' });
  expect(patches(calls, 'invoices')[0]).toMatchObject({ total_amount: 1200, amount_paid: 500, status: 'unpaid' });
  expect(posts(calls, 'cash_movements').length).toBe(0);
});

test('other-currency sale keeps the old edit page', async ({ page }) => {
  await install(page, { db: base({ id: 's4', status: 'paid', payment_method: 'cash', total_amount: 950, amount_paid: 950, pay_currency: 'SYP', pay_fx_rate: 13000, items: [] }) });
  await page.goto('/new-sale-ar.html?edit=s4');
  await expect(page).toHaveURL(/invoice-edit-ar\.html\?id=s4/);
});

test('customer with a deposit: the sale screen says it is taken off what stays unpaid', async ({ page }) => {
  await install(page, { db: base({ id: 'x', status: 'paid', payment_method: 'cash', total_amount: 0, amount_paid: 0, items: [] }),
    rpc: { customer_credit: () => ({ body: 2000 }) } });
  await page.goto('/new-sale-ar.html?draft=none');
  await page.evaluate(() => { pickCustomer({ id: 'c1', name: 'رجاء', phone: '050' }); cart.push({ cartId: 1, piece: null, barcode: null, karat: 18, weight: 10, price: 24800, description: 'طقم' }); renderCart(); });
  await expect(page.locator('#customer-credit')).toContainText('2,000');
  await page.click('#pay-mixed');
  await page.fill('#mixed-cash-amount', '10000');
  await expect(page.locator('#mixed-credit')).toContainText('2,000');
  await expect(page.locator('#mixed-remaining-note')).toContainText('12,800');
});

test('after saving, it goes back to the page the invoice was opened from', async ({ page }) => {
  await install(page, { db: base({ id: 's5', status: 'paid', payment_method: 'cash', total_amount: 100, amount_paid: 100,
    items: [{ id: 'l1', invoice_id: 's5', karat: 18, weight_grams: 1, line_total: 100, description: 'خاتم' }] }),
    rpc: { accounting_health_check: () => ({ body: [] }) } });
  await page.goto('/accounting-check-ar.html');
  await openEdit(page, 's5');
  await setPrice(page, 0, 120);
  await page.click('#save-invoice-btn');
  await expect(page).toHaveURL(/accounting-check-ar\.html$/);
});

test('deposits list: a deposit used on an invoice shows as used and cannot be refunded', async ({ page }) => {
  await install(page, { db: base({ id: 'x', status: 'paid', payment_method: 'cash', total_amount: 0, amount_paid: 0, items: [] }, {
    customer_deposits: [{ id: 'd1', store_id: STORE, deposit_number: 'DEP-000002', customer_id: 'c1', amount: 2000, method: 'cash', status: 'active', items: [], created_at: '2026-10-10T08:00:00Z', customer: { name: 'رجاء' } }]
  }), rpc: { customer_deposit_remaining: () => ({ body: [{ deposit_id: 'd1', remaining: 0 }] }) } });
  await page.goto('/deposits-ar.html');
  await expect(page.locator('#list')).toContainText('استُخدم في فاتورة');
  await page.locator('#list button').first().click();
  await expect(page.locator('#voucher')).toContainText('استُخدم كاملاً');
  await expect(page.locator('#voucher button[onclick="refundDeposit()"]')).toHaveCount(0);
});
