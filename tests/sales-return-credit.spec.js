// بشار 2026-11-23: a sales return can leave the money on the customer's account (عربون) instead of paying it out.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const base = (inv) => ({ stores: [{ id: STORE, name: 'x', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  invoices: [inv], invoice_items: [{ id: 'it1', invoice_id: inv.id, barcode: '001', karat: 21, weight_grams: 5, line_total: 500, description: 'خاتم' }] });

test('cash sale to a customer: «keep as credit» is offered and sent as customer_credit', async ({ page }) => {
  let sent = null;
  await install(page, { generic: true, db: base({ id: 'i1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', payment_method: 'cash', total_amount: 500, customer_id: 'c1', customer: { name: 'نسرين' } }),
    rpc: { post_sales_return: (a) => { sent = a.p; return { body: { id: 'r1', invoice_number: 'RET-1', total: 500 } }; } } });
  page.on('dialog', d => d.accept());
  await page.goto('/sales-return-ar.html');
  await page.fill('#searchInput', 'INV-1');
  await page.evaluate(() => searchInvoice());
  await expect(page.locator('#refundMethod option[value="customer_credit"]')).toHaveText('يبقى بحساب العميل رصيداً (عربون)');
  await page.selectOption('#refundMethod', 'customer_credit');
  await page.locator('#items-list input[type=checkbox]').first().check();
  await page.click('#submit-btn');
  await expect.poll(() => sent && sent.refund_method, { timeout: 8000 }).toBe('customer_credit');
});

test('walk-in sale (no customer): no credit option', async ({ page }) => {
  await install(page, { generic: true, db: base({ id: 'i2', store_id: STORE, invoice_number: 'INV-2', type: 'sale', status: 'paid', payment_method: 'cash', total_amount: 500, customer_id: null }) });
  await page.goto('/sales-return-ar.html');
  await page.fill('#searchInput', 'INV-2');
  await page.evaluate(() => searchInvoice());
  await expect(page.locator('#refundMethod option')).toHaveCount(2);
  await expect(page.locator('#refundMethod option[value="customer_credit"]')).toHaveCount(0);
});
