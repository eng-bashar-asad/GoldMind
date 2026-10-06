// "ربح السند" on a give-out voucher in the trader's movements: owner sees the voucher's own profit.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-10-06T10:00:00Z';
const pc = { cost_fabrication_per_gram: 6, accounting_weight_grams: 9, weight_grams: 10 };
const mv = id => ({ id, store_id: STORE, trader_id: 't1', movement_type: 'debt_decrease', source: 'stock_given', batch_id: 'b1', piece_id: 'p' + id,
  karat: 18, weight_grams: 10, accounting_weight_grams: 10, gold_24k_equivalent: 7.5, fab_fee_per_gram: 15, fab_fee_amount: 150,
  piece_acc_weight: 9, gold_price_24k: 100, created_at: T, piece: pc });

test('voucher profit popup', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }], pieces: [],
    gold_prices: [{ store_id: STORE, karat: 24, price_per_gram: 120 }],
    trader_movements: [mv('1'), mv('2')]
  } });
  await page.goto('/ledger-ar.html?trader=t1');
  const btn = page.locator('#trader-batch-b1 button', { hasText: 'ربح السند' });
  await expect(btn).toBeVisible();
  await btn.click();
  // per piece: making 15×10 − 6×9 = 96, gold 0.75 g × 100 = 75 → 171; two pieces → 342
  await expect(page.locator('#gm-vp-total')).toHaveText('342.00');
  await expect(page.locator('#gm-vp-body')).toContainText('192.00');  // making profit
  await expect(page.locator('#gm-vp-body')).toContainText('1.500');   // diff 24k
  await expect(page.locator('#gm-vp-body')).toContainText('180.00');  // value now
  expect(errs).toEqual([]);
});
