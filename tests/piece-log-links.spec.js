// Piece history: an invoice number in a line opens that invoice; a trader line opens the trader voucher.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('piece history links to the invoice and the trader voucher', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000100', status: 'sold', weight_grams: 10, karat: 18 }],
    piece_movements: [
      { id: 'm1', store_id: STORE, piece_id: 'p1', event_type: 'sold', note: 'بيع بفاتورة INV-2026-000026', created_at: '2026-10-08T10:00:00Z' },
      { id: 'm2', store_id: STORE, piece_id: 'p1', event_type: 'given_to_trader', note: 'إعطاء بضاعة للتاجر', created_at: '2026-10-01T10:00:00Z' }],
    invoices: [{ id: 'inv26', store_id: STORE, invoice_number: 'INV-2026-000026' }],
    trader_movements: [{ id: 't1', store_id: STORE, piece_id: 'p1', trader_id: 'tr1', batch_id: 'b1', source: 'stock_given', created_at: '2026-10-01T10:00:01Z', trader: { name: 'جليل' } }]
  } });
  await page.goto('/piece-edit-ar.html?id=p1');
  const link = page.locator('#piece-log-list a', { hasText: 'INV-2026-000026' });
  await expect(link).toHaveAttribute('href', 'invoice-print-ar.html?id=inv26');
  await expect(page.locator('#piece-log-list a', { hasText: 'فتح السند' })).toHaveAttribute('href', 'trader-statement-print-ar.html?trader=tr1&batch=b1');
});
