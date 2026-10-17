// All invoices: one filter for every kind of document (customer/trader sales, scrap purchases,
// goods in/out, trader cash in/out, customer payments).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-10-10T10:00:00Z';

test('section filter shows each kind of document', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [
      { id: 'i1', store_id: STORE, invoice_number: 'S-9', type: 'sale', status: 'paid', total_amount: 100, created_at: T, customer: { name: 'زبون أ' } },
      { id: 'i2', store_id: STORE, invoice_number: 'PINV-1', type: 'buyRetail', status: 'paid', total_amount: 50, created_at: T, customer: { name: 'زبون ب' } }],
    invoice_items: [], repair_tickets: [],
    trader_movements: [
      { id: 'm1', store_id: STORE, trader_id: 't1', source: 'stock_given', batch_id: 'b1', batch_ref: 'OUT-7', gold_24k_equivalent: 7.5, fab_fee_amount: 150, created_at: T, trader: { name: 'جليل' } },
      { id: 'm2', store_id: STORE, trader_id: 't1', source: 'stock_given', batch_id: 'b1', batch_ref: 'OUT-7', gold_24k_equivalent: 2.5, fab_fee_amount: 50, created_at: T, trader: { name: 'جليل' } },
      { id: 'm3', store_id: STORE, trader_id: 't2', source: 'cash_out', fab_fee_amount: 20, created_at: T, trader: { name: 'حمدي' } },
      { id: 'm4', store_id: STORE, trader_id: 't2', source: 'cash_in', fab_fee_amount: 70, created_at: T, trader: { name: 'حمدي' } }],
    stock_vouchers: [{ id: 'v1', store_id: STORE, direction: 'out', voucher_number: 'SV-1', created_at: T, party: { name: 'فرع' } }],
    customer_debts: [{ id: 'd1', store_id: STORE, customer_id: 'c1', source: 'payment', cash_amount: 30, created_at: T, customer: { name: 'زبون أ' } }],
  } });
  await page.goto('/invoices-list-ar.html');
  const list = page.locator('#results-list');
  const pick = async (v, has, not) => {
    await page.selectOption('#typeFilter', v);
    for (const h of has) await expect(list).toContainText(h);
    for (const n of not) await expect(list).not.toContainText(n);
  };
  await pick('sale', ['S-9'], ['PINV-1', 'OUT-7']);
  await pick('buyRetail', ['PINV-1'], ['S-9']);
  await pick('traderSale', ['OUT-7', '10.00 غ ع24', '200.00'], ['S-9', 'سند كاش']);
  await pick('stockOut', ['SV-1'], ['OUT-7']);
  await pick('traderCashOut', ['حمدي', '20.00'], ['70.00']);
  await pick('traderCashIn', ['70.00'], ['20.00']);
  await pick('customerPay', ['زبون أ', '30.00'], ['S-9']);
  await expect(list.locator('a[href="customer-debts-ar.html?open=c1"]')).toHaveCount(1);
  expect(errs).toEqual([]);
});
