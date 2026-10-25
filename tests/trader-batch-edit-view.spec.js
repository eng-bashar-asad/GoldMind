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

// Returning one piece from a give-out voucher: the piece goes back to stock through trader_return_piece.
test('voucher edit: «إرجاع للمخزن» returns one piece and keeps the voucher open', async ({ page }) => {
  const asked = [];
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'هادي' }],
    pieces: [{ id: 'pc1', store_id: STORE, barcode: '000718' }, { id: 'pc2', store_id: STORE, barcode: '000713' }],
    trader_movements: [
      { id: 'm1', store_id: STORE, trader_id: 't1', batch_id: 'b1', piece_id: 'pc1', movement_type: 'debt_increase', source: 'stock_given', weight_grams: 9.58, accounting_weight_grams: 9.58, karat: 18, gold_24k_equivalent: 7.19, fab_fee_per_gram: 10, fab_fee_amount: 95.8, created_at: ago(2) },
      { id: 'm2', store_id: STORE, trader_id: 't1', batch_id: 'b1', piece_id: 'pc2', movement_type: 'debt_increase', source: 'stock_given', weight_grams: 9.5, accounting_weight_grams: 9.5, karat: 18, gold_24k_equivalent: 7.13, fab_fee_per_gram: 10, fab_fee_amount: 95, created_at: ago(2) },
    ],
  }, rpc: { trader_return_piece: (b) => { asked.push(b); return { body: { ok: true, barcode: '000713' } }; } } });
  page.on('dialog', d => d.accept());
  await page.goto('/ledger-ar.html?trader=t1');
  await page.locator('button', { hasText: 'تعديل' }).first().click();
  const form = page.locator('#edit-batch-form-b1');
  await form.locator('button', { hasText: 'إرجاع للمخزن' }).nth(1).click();
  await expect.poll(() => asked.length).toBe(1);
  expect(asked[0]).toEqual({ p_movement: 'm2' });
  await expect(page.locator('#edit-batch-form-b1')).not.toHaveClass(/\bhidden\b/);
});
