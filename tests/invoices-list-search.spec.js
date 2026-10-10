// All-invoices list: amount in the paid currency, barcodes shown and searchable (also beyond the loaded 300).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-10-01T10:00:00Z';

test('paid currency and barcodes', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'ب' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    repair_tickets: [],
    invoices: [
      { id: 'i1', store_id: STORE, invoice_number: 'INV-26', type: 'sale', status: 'paid', total_amount: 100, currency: 'USD', pay_currency: 'SYP', pay_fx_rate: 13000, created_at: T },
      { id: 'i2', store_id: STORE, invoice_number: 'INV-27', type: 'sale', status: 'paid', total_amount: 50, currency: 'USD', pay_breakdown: [{ currency: 'USD', amount: 20 }, { currency: 'SYP', amount: 390000 }], created_at: T }],
    invoice_items: [
      { id: 'a', invoice_id: 'i1', barcode: '000628', weight_grams: 5, karat: 21 },
      { id: 'b', invoice_id: 'i1', barcode: '000648', weight_grams: 5, karat: 21 },
      { id: 'c', invoice_id: 'i2', barcode: '000900', weight_grams: 5, karat: 21 }]
  } });
  await page.goto('/invoices-list-ar.html');
  await expect(page.locator('.inv-day')).toHaveCount(1);
  await expect(page.locator('.inv-day')).toContainText('01/10/2026');
  await expect(page.locator('.inv-day')).toContainText('2 مستندات');
  const card1 = page.locator('a', { hasText: 'INV-26' });
  await expect(card1.locator('.inv-amount')).toHaveText('1,300,000 SYP');
  await expect(card1).toContainText('100.00 USD');
  await expect(card1.locator('.inv-bc')).toContainText('000628');
  await expect(page.locator('a', { hasText: 'INV-27' }).locator('.inv-split')).toHaveText('20 USD + 390,000 SYP');
  await page.fill('#searchInput', '000648');
  await expect(page.locator('#results-list a')).toHaveCount(1);
  await expect(page.locator('#results-list a')).toContainText('INV-26');
});
