// "عرض الربح" on an invoice must subtract accent diamonds (Di) like the profit report does.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('invoice profit subtracts accent diamond cost', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD', vat_rate: 1 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'b' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [{ id: 'inv1', store_id: STORE, invoice_number: 'INV-2026-000001', type: 'sale', total_amount: 3600, vat_amount: 0, status: 'paid', created_at: '2026-09-27T14:11:09Z', payment_method: 'cash', customer_id: 'c1' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'زبون' }],
    invoice_items: [{ id: 'i1', invoice_id: 'inv1', barcode: 'M A 460 W', karat: 18, weight_grams: 15.03, accounting_weight_grams: 14.24, line_total: 3600, gold_price_per_gram: 103.45, fabrication_fee: 0,
      piece: { cost_fabrication_per_gram: 31.6, accent_diamond_carat: 0.39, accent_diamond_price_per_carat: 500 }, lot: null, diamond: null }],
    gold_prices: [], pieces: [], traders: [],
  } });
  await page.goto('/invoice-print-ar.html?id=inv1');
  await expect(page.locator('#profit-total')).not.toHaveText('');
  // 3600 − 14.24×103.45 − (3600 − 3600/1.01) − 14.24×31.6 − 0.39×500 = 1446.24
  await expect(page.locator('#profit-total')).toHaveText('1446.24');
});
