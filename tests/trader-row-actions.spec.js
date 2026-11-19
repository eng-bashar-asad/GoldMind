// Computer: clicking a statement row opens its actions in a strip under the row (no side «سجل الحركات» column); clicking again closes it.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('statement row opens its actions inline', async ({ page }) => {
  await page.setViewportSize({ width: 1400, height: 900 });
  const mv = (id, w) => ({ id, store_id: STORE, trader_id: 't1', batch_id: 'b1', movement_type: 'debt_decrease', source: 'stock_given',
    weight_grams: w, accounting_weight_grams: w, karat: 18, gold_24k_equivalent: w * 0.75, fab_fee_per_gram: 10, fab_fee_amount: w * 10, created_at: '2026-11-19T10:00:00Z' });
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }], gold_prices: [], pieces: [],
    trader_movements: [mv('m1', 10), mv('m2', 6)]
  } });
  await page.goto('/ledger-ar.html?trader=t1');
  const row = page.locator('.ld-st tbody tr.ld-row').first();
  await row.click();
  const strip = page.locator('.ld-st tr.ld-exp');
  await expect(strip).toHaveCount(1);
  await expect(strip.locator('button', { hasText: 'ربح السند' })).toBeVisible();
  await expect(strip.locator('button', { hasText: 'تعديل' }).first()).toBeVisible();
  await expect(strip.locator('a', { hasText: 'القطع' })).toBeVisible();
  await expect(page.locator('#movements-list')).toBeHidden();
  await expect(page.locator('#gm-moves-col > h3')).toBeHidden();
  await expect(page.getByText('إظهار / إخفاء تفاصيل الحركات')).toHaveCount(0);
  // the edit form opens inside the strip
  await strip.locator('button', { hasText: 'تعديل' }).first().click();
  await expect(strip.locator('#edit-batch-form-b1')).toBeVisible();
  await row.click();
  await expect(strip).toHaveCount(0);
  await expect(page.locator('#movements-list #trader-batch-b1')).toHaveCount(1); // card went back
});
