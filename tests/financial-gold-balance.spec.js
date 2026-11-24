// بشار 2026-11-24: «ميزان الذهب» — sold vs scrap bought in 24k, average 24k gram price, ounce in USD.
// Only for whoever may see it; the report shows only the sections picked.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const now = new Date().toISOString();
const db = (perm, role) => ({
  stores: [{ id: STORE, name: 'محل', currency: 'AED', vat_rate: 0, last_gold_ounce_rate: 3.6725 }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role, permissions: perm, full_name: 'x' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  invoices: [
    { id: 's1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', payment_method: 'cash', total_amount: 5000, amount_paid: 5000, created_at: now },
    { id: 'b1', store_id: STORE, invoice_number: 'PINV-1', type: 'buyRetail', status: 'paid', payment_method: 'cash', total_amount: 3200, amount_paid: 3200, created_at: now },
  ],
  invoice_items: [
    // 24 g of 18k at 300/g → 18 g of 24k worth 7200 → 400 a 24k gram
    { id: 'l1', invoice_id: 's1', karat: 18, weight_grams: 24.5, accounting_weight_grams: 24, line_total: 9000, gold_price_per_gram: 300, fabrication_fee: 0, piece: { cost_fabrication_per_gram: 0 }, lot: null, diamond: null },
    // scrap: 10 g of 21k (8.75 g 24k) for 3200 → 365.71 a 24k gram
    { id: 'l2', invoice_id: 'b1', karat: 21, weight_grams: 10, accounting_weight_grams: 10, line_total: 3200, gold_stock_lot_id: 'lot1' },
  ],
  expense_entries: [], daily_cash_log: [], customer_debts: [], trader_movements: [],
  pieces: [{ store_id: STORE, karat: 18, weight_grams: 13, accounting_weight_grams: 12, status: 'available' }],
  gold_stock_lots: [{ store_id: STORE, karat: 21, weight_grams_remaining: 8, box_name: 'كسر 21' }], gold_prices: [], diamond_pieces: [],
});
const run = async page => { await page.addInitScript(() => localStorage.setItem('gm_fr_period', 'today')); await page.goto('/financial-report-ar.html'); };

test('owner: picks «ميزان الذهب» alone and gets averages + USD ounce', async ({ page }) => {
  await install(page, { db: db({}, 'owner') });
  await page.addInitScript(() => localStorage.setItem('gm_fr_secs', JSON.stringify(['goldbal'])));
  await run(page);
  await page.locator('#fr-controls:not(.hidden) #fr-run').click();
  const b = page.locator('#fr-body');
  await expect(b).toContainText('ميزان الذهب');
  await expect(b).toContainText('18.00 غ');            // sold, 24k
  await expect(b).toContainText('400.00 AED');          // sold avg 24k gram
  await expect(b).toContainText('$ 3,387.72');          // 400 × 31.1035 ÷ 3.6725
  await expect(b).toContainText('8.75 غ');              // scrap bought, 24k
  await expect(b).toContainText('365.71 AED');
  await expect(b).toContainText('بعنا أكثر مما اشترينا');
  // per karat with its 24k equivalent; stock now (pieces 12 g 18k = 9, scrap 8 g 21k = 7) → shop 16 g 24k
  await expect(b.locator('tr', { hasText: 'المجموع' })).toHaveCount(0); // one karat each: no total rows
  await expect(b).toContainText('صناديق القطع المتوفرة الآن');
  await expect(b).toContainText('9.00 غ');
  await expect(b).toContainText('7.00 غ');
  await expect(b.locator('tr', { hasText: 'رصيد المحل كاملاً' })).toContainText('16.00 غ');
  await expect(b).not.toContainText('المبيعات');        // only the picked section
});

test('staff without the permission: no gold-balance option at all', async ({ page }) => {
  await install(page, { db: db({ view_reports: true, view_profit_report: true }, 'staff') });
  await page.addInitScript(() => localStorage.setItem('gm_fr_secs', JSON.stringify(['goldbal', 'sales'])));
  await run(page);
  await expect(page.locator('#fr-secs input[data-sec="sales"]')).toBeAttached();
  await expect(page.locator('#fr-secs input[data-sec="goldbal"]')).toHaveCount(0);
  await page.locator('#fr-controls:not(.hidden) #fr-run').click();
  await expect(page.locator('#fr-body')).toContainText('المبيعات');
  await expect(page.locator('#fr-body')).not.toContainText('ميزان الذهب');
});
