// Plan 1.3: printouts take the legal identity (TRN, registration, logo) from the organization
// via store_legal(), while the branch keeps its own name.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('invoice print uses the organization TRN and registration, branch name stays', async ({ page }) => {
  await install(page, {
    db: {
      stores: [{ id: STORE, name: 'فرع ديرة', currency: 'AED', vat_rate: 5, tax_number: null, legal_registration_id_type: null }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'b' }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      invoices: [{ id: 'inv1', store_id: STORE, invoice_number: 'INV-2026-000001', type: 'sale', total_amount: 1050, vat_amount: 50, status: 'paid', created_at: '2026-10-14T10:00:00Z', payment_method: 'cash', customer_id: null }],
      invoice_items: [{ id: 'i1', invoice_id: 'inv1', barcode: 'A1', karat: 21, weight_grams: 3, line_total: 1050, gold_price_per_gram: 300, fabrication_fee: 0, piece: null, lot: null, diamond: null }],
      customers: [], gold_prices: [], pieces: [], traders: [],
    },
    rpc: {
      store_legal: () => ({ body: [{ organization_name: 'المنشأة', legal_name: 'Org LLC', tax_number: '100200300400003', commercial_registration_number: 'CR-9', legal_registration_id_type: 'TL' }] }),
    },
  });
  await page.goto('/invoice-print-ar.html?id=inv1');
  await expect(page.locator('#store-legal')).toHaveText('Trade Licence No. CR-9 | TRN: 100200300400003');
  await expect(page.locator('#doc-type-ar')).toHaveText('فاتورة ضريبية');
  await expect(page.locator('body')).toContainText('فرع ديرة');
});
