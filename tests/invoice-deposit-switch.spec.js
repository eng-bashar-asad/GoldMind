// Editing a sale invoice: switch between "paid partly from the deposit" and "paid in full in cash".
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = extra => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  invoices: [{ id: 's1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', payment_method: 'cash', customer_id: 'c1', total_amount: 2200, amount_paid: 2200, created_at: '2026-11-14T07:00:00Z' }],
  invoice_items: [{ id: 'it1', invoice_id: 's1', karat: 18, weight_grams: 10, line_total: 2200, description: 'إسوارة' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'مصطفى', phone: '1' }], pieces: [],
  ...extra
});

for (const used of [true, false]) test('invoice edit: deposit switch — ' + (used ? 'release' : 'use'), async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  let sent = null;
  await install(page, {
    db: db({ daily_cash_log: used ? [{ id: 'l1', store_id: STORE, link_group: 'dep_s1', operation_type: 'عربون سابق', direction: 'out', amount: 1000 }] : [] }),
    rpc: { customer_credit: () => ({ body: used ? 0 : 500 }), invoice_set_deposit: a => { sent = a; return { body: 1000 }; } }
  });
  page.on('dialog', d => d.accept());
  await page.goto('/invoice-edit-ar.html?id=s1');
  await expect(page.locator('#depBox')).toContainText(used ? '1,000.00' : '500.00');
  await page.click('#depBox button');
  await expect.poll(() => sent).toEqual({ p_invoice: 's1', p_use: !used });
  expect(errs).toEqual([]);
});

test('sale-screen edit (computer) also offers the deposit switch', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  let sent = null;
  await install(page, {
    db: db({ daily_cash_log: [{ id: 'l1', store_id: STORE, link_group: 'dep_s1', operation_type: 'عربون سابق', direction: 'out', amount: 1000 }],
      gold_prices: [], diamond_pieces: [], gold_stock_lots: [] }),
    rpc: { customer_credit: () => ({ body: 0 }), invoice_set_deposit: a => { sent = a; return { body: 1000 }; } }
  });
  page.on('dialog', d => d.accept());
  await page.goto('/new-sale-ar.html?edit=s1');
  await expect(page.locator('#dep-box')).toContainText('1,000.00');
  await page.click('#dep-box button');
  await expect.poll(() => sent).toEqual({ p_invoice: 's1', p_use: false });
  expect(errs).toEqual([]);
});
