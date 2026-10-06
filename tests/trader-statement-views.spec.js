// Trader statement: ↑/↓ arrows instead of long labels, "سندات" (one row per voucher)
// vs "تفاصيل" (every piece), photos on/off, and short descriptions.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-09-30T10:00:00Z';
const mv = (id, pid, bc, w24, fab) => ({ id, store_id: STORE, trader_id: 't1', movement_type: 'debt_decrease', source: 'stock_given', batch_id: 'b1', piece_id: pid, karat: 18, weight_grams: w24 * 4 / 3, gold_24k_equivalent: w24, fab_fee_amount: fab, notes: `إخراج بضاعة — باركود ${bc} (خاتم)`, created_at: T });
const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  traders: [{ id: 't1', store_id: STORE, name: 'تاجر أ', phone: '0999' }],
  pieces: [{ id: 'p1', store_id: STORE, barcode: '000436', photo_url: 'https://example.com/a.jpg' }, { id: 'p2', store_id: STORE, barcode: '000415' }],
  trader_movements: [mv('m1', 'p1', '000436', 7.5, 150), mv('m2', 'p2', '000415', 15, 300),
    { id: 'm3', store_id: STORE, trader_id: 't1', movement_type: 'debt_increase', source: 'cash_in', gold_24k_equivalent: 0, fab_fee_amount: 100, created_at: T }],
});

test('vouchers vs details, arrows, photos toggle', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await page.addInitScript(() => { try { localStorage.clear(); } catch (e) {} });
  await install(page, { db: db() });
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  const rows = page.locator('#stGoldRows');
  await expect(rows.locator('tr.st-v')).toHaveCount(1);
  await expect(rows.locator('tr.st-p')).toHaveCount(0);
  await expect(rows).toContainText('arrow_upward');
  await expect(rows).toContainText('30.00');      // billed weight 10 + 20
  await expect(rows).toContainText('22.50');        // 24k total
  await expect(rows).toContainText('450.00');   // making total
  await expect(rows).not.toContainText('إعطاء بضاعة');
  await expect(page.locator('#stCashRows')).toContainText('arrow_downward');
  await expect(page.locator('#stCashRows')).not.toContainText('450'); // making not repeated

  await page.click('#stOpts [data-view=details]');
  await expect(rows.locator('tr.st-p')).toHaveCount(2);
  await expect(rows).toContainText('000436 (خاتم)');
  await expect(rows).not.toContainText('إخراج بضاعة');
  await expect(rows.locator('img.st-ph')).toHaveCount(1);
  await page.click('#stOpts [data-photos="0"]');
  await expect(rows.locator('img.st-ph')).toHaveCount(0);
  expect(errs).toEqual([]);
});
