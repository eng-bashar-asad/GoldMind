// Multi-branch 2.1: a customer's account shows every branch; another branch's rows give balance and date only.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  stores: [{ id: STORE, currency: 'AED', name: 'فرع ب' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'staff', permissions: { view_customers: true, edit_customers: true, view_past_days: true } }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  customers: [{ id: 'cu1', store_id: 'branch-a', name: 'راما مملوك', phone: '0501' }],
  customer_debts: [
    { id: 'm1', store_id: 'branch-a', customer_id: 'cu1', invoice_id: 'inv-a', movement_type: 'debt_increase', cash_amount: 1000, gold_grams_24k: 0,
      notes: 'فاتورة بيع INV-2026-000050', source: null, created_at: '2026-09-01T10:00:00Z', invoice: { invoice_number: 'INV-2026-000050' } },
  ],
  invoices: [], customer_phones: [], company_kyc_documents: [], customer_deposits: [],
});
const branches = [{ id: STORE, name: 'فرع ب', can_open_invoices: true }, { id: 'branch-a', name: 'فرع أ', can_open_invoices: false }];

test('another branch: balance, date and branch shown; invoice number, notes and link hidden', async ({ page }) => {
  await install(page, { db: db(), rpc: { org_branches: () => ({ body: branches }) } });
  await page.setViewportSize({ width: 390, height: 844 }); // phone cards (the computer shows a statement table)
  await page.goto('/customer-debts-ar.html?open=cu1');
  const row = page.locator('#movements-list > *').first();
  await expect(row).toContainText('فرع أ');
  await expect(row).toContainText('1,000');
  await expect(row).not.toContainText('INV-2026-000050');
  expect(await row.evaluate(el => el.tagName)).toBe('DIV'); // not a link
});

test('a payment taken here is sent with this branch', async ({ page }) => {
  const calls = await install(page, { db: db(), rpc: { org_branches: () => ({ body: branches }), record_customer_payment: () => ({ body: { ok: true } }) } });
  await page.setViewportSize({ width: 390, height: 844 }); // phone cards (the computer shows a statement table)
  await page.goto('/customer-debts-ar.html?open=cu1');
  await expect(page.locator('#detail-customer-name')).not.toBeEmpty();
  await page.evaluate(() => toggleSettleForm());
  await page.fill('#settle-amount', '400');
  await page.click('#settle-btn');
  await expect.poll(() => calls.some(c => c.name === 'record_customer_payment')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'record_customer_payment').body)).toMatchObject({ p_customer: 'cu1', p_amount: 400, p_store: STORE });
});
