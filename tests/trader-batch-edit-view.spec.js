// Editing a stock-given voucher shows each piece with its barcode and photo.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const ago = d => new Date(Date.now() - d * 86400000).toISOString();

test('voucher edit form lists each piece with its barcode and photo', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
    pieces: [{ id: 'pc1', store_id: STORE, barcode: '000709', photo_url: 'https://example.invalid/p.jpg' }],
    trader_movements: [
      { id: 'm1', store_id: STORE, trader_id: 't1', batch_id: 'b1', piece_id: 'pc1', movement_type: 'debt_increase', source: 'stock_given',
        weight_grams: 9.21, accounting_weight_grams: 9.21, karat: 18, gold_24k_equivalent: 6.91, fab_fee_per_gram: 10, fab_fee_amount: 92.1, created_at: ago(2) },
    ],
  } });
  await page.goto('/ledger-ar.html?trader=t1');
  await page.locator('button', { hasText: 'تعديل' }).first().click();
  const form = page.locator('#edit-batch-form-b1');
  await expect(form).toContainText('000709');
  await expect(form.locator('img')).toHaveAttribute('src', 'https://example.invalid/p.jpg');
  await expect(form.locator('input[id^="edit-batch-weight-"]')).toHaveValue('9.21');
  await expect(form.locator('select[id^="edit-batch-karat-"]')).toHaveValue('18');
});
