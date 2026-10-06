// Customer page: profit of one invoice without opening it, and total profit with the customer for a period.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-10-03T10:00:00Z';

test('invoice profit button and customer period profit', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message + ' @ ' + (e.stack || '').split('\n').slice(1,3).join(' ')));
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD', vat_rate: 0 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'حسن درويش', phone: '0944' }],
    gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 100 }],
    invoices: [{ id: 'i1', store_id: STORE, customer_id: 'c1', invoice_number: 'INV-15', type: 'sale', status: 'paid', payment_method: 'cash', total_amount: 1300, amount_paid: 1300, created_at: T }],
    // 10 g acc @100 = 1000 gold, making cost 2/g = 20 → profit 280
    invoice_items: [{ id: 'it1', invoice_id: 'i1', barcode: '000001', karat: 18, weight_grams: 10, accounting_weight_grams: 10, line_total: 1300, gold_price_per_gram: 100, piece: { cost_fabrication_per_gram: 2 } }],
    customer_debts: [{ id: 'd1', store_id: STORE, customer_id: 'c1', movement_type: 'debt_decrease', source: 'discount', cash_amount: 30, created_at: T }]
  } });
  await page.goto('/customer-debts-ar.html?open=c1');
  const card = page.locator('a[href="invoice-print-ar.html?id=i1"]');
  await expect(card).toBeVisible();
  await card.locator('button', { hasText: 'ربح الفاتورة' }).click();
  await expect(page).toHaveURL(/customer-debts/);            // stayed on the page
  await expect(page.locator('#gm-profit-total')).toHaveText('280.00');
  await page.locator('#gm-profit-modal button[aria-label="إغلاق"]').click();
  await page.click('button:has-text("أرباحي مع هذا الزبون")');
  await expect(page.locator('#gm-pp-total')).toHaveText('250.00'); // 280 − 30 discount
  expect(errs.filter(e => !e.includes('_getFinalPath'))).toEqual([]); // storage listing isn't faked
});
