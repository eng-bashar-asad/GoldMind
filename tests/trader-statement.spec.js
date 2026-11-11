// Trader statement (بشار 2026-11-10): one line per voucher, out/in chip, gold and making on the same line,
// running balance oldest → newest whatever order the rows come in.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const O = { store_id: STORE, trader_id: 't0' };
test('statement: a two-piece voucher is one line, directions and balances are right', async ({ page }) => {
  await install(page, { generic: true, realCdn: true, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't0', store_id: STORE, name: 'هادي' }],
    trader_movements: [
      { id: 'r', ...O, movement_type: 'debt_increase', source: 'cash_in', fab_fee_amount: 50, gold_24k_equivalent: 0, voucher_no: 'REC-1', created_at: '2026-11-03T10:00:00Z' },
      { id: 'a', ...O, movement_type: 'debt_decrease', source: 'stock_given', batch_id: 'B', weight_grams: 8, accounting_weight_grams: 8, karat: 18, gold_24k_equivalent: 6, fab_fee_amount: 80, voucher_no: 'TOUT-1', created_at: '2026-11-01T10:00:00Z' },
      { id: 'b', ...O, movement_type: 'debt_decrease', source: 'stock_given', batch_id: 'B', weight_grams: 4, accounting_weight_grams: 4, karat: 18, gold_24k_equivalent: 3, fab_fee_amount: 40, voucher_no: 'TOUT-1', created_at: '2026-11-01T10:00:00Z' }] } });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/ledger-ar.html?trader=t0');
  const rows = page.locator('#ldStatement tbody tr');
  await expect(rows).toHaveCount(2);
  // on the computer it sits right under the account card, not a screen further down (row gaps × 40 spanned rows)
  const top = await page.locator('#ldStatement').evaluate(e => e.getBoundingClientRect().top);
  expect(top).toBeLessThan(700);
  await expect(rows.nth(0)).toContainText('صادر للتاجر');
  await expect(rows.nth(0)).toContainText('2 قطع');
  await expect(rows.nth(0).locator('td[data-l="الوزن القائم"]')).toContainText('12');
  await expect(rows.nth(0).locator('td[data-l="المبلغ"]')).toContainText('120');
  await expect(rows.nth(1)).toContainText('وارد من التاجر');
  await expect(rows.nth(1).locator('td[data-l="الرصيد النقدي بعدها"]')).toContainText('70');
  await expect(rows.nth(1).locator('td[data-l="رصيد الذهب بعدها"]')).toContainText('9');
});
