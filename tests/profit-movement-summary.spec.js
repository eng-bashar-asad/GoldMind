// Owner's movement summary at the top of the profit report: customer sales and goods out to traders by karat,
// profit of all sales, and gold in stock now by karat (barcoded pieces vs scrap).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-09-15T10:00:00Z';

test('movement summary: by karat, total sales profit, stock now split', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', vat_rate: 0 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    gold_prices: [{ store_id: STORE, karat: 24, price_per_gram: 120 }],
    invoices: [{ id: 'i1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', total_amount: 1300, created_at: T, created_by: STAFF }],
    invoice_items: [
      { id: 'l1', invoice_id: 'i1', karat: 18, weight_grams: 10, accounting_weight_grams: 9, line_total: 1000, gold_price_per_gram: 80, piece: { cost_fabrication_per_gram: 5 }, lot: null, diamond: null },
      { id: 'l2', invoice_id: 'i1', karat: 21, weight_grams: 2, accounting_weight_grams: 2, line_total: 300, gold_price_per_gram: 100, piece: { cost_fabrication_per_gram: 5 }, lot: null, diamond: null }],
    trader_movements: [{ id: 'm1', store_id: STORE, source: 'stock_given', batch_id: 'b1', weight_grams: 10, accounting_weight_grams: 10, piece_acc_weight: 9,
      gold_price_24k: 100, karat: 18, gold_24k_equivalent: 7.5, fab_fee_per_gram: 15, fab_fee_amount: 150, created_at: T,
      trader: { name: 'جليل' }, piece: { barcode: '000001', cost_fabrication_per_gram: 6, accounting_weight_grams: 9, weight_grams: 10 } }],
    pieces: [{ store_id: STORE, status: 'available', karat: 18, weight_grams: 100, accounting_weight_grams: 98 }],
    gold_stock_lots: [{ store_id: STORE, karat: 18, weight_grams_remaining: 20 }],
    diamond_pieces: [], expense_entries: [], customer_debts: [],
  } });
  await page.goto('/profit-report-ar.html');
  await page.fill('#date-from', '2026-09-01');
  await page.fill('#date-to', '2026-09-30');
  await page.click('#apply-filters-btn');
  const br = page.locator('#pr-brief');
  await expect(br).toContainText('1300.00'); // the September run has painted
  const cells = async (section, rowText) => br.locator('div.gm-keep', { hasText: section }).locator('tr', { hasText: rowText }).first().locator('td').allInnerTexts();

  // customers 18k: 10 g gross, 9 acc → 6.75 g 24k, 1000; profit 1000 − 9×80 − 9×5 = 235
  expect(await cells('مبيعات الزبائن حسب العيار', /^18/)).toEqual(['18', '10.000', '9.000', '6.750', '1000.00', '235.00']);
  // 21k: 2 g → 1.75 g 24k, 300; profit 300 − 200 − 10 = 90
  expect(await cells('مبيعات الزبائن حسب العيار', 'المجموع')).toEqual(['المجموع', '12.000', '11.000', '8.500', '1300.00', '325.00']);
  // traders 18k: 10 g billed, 7.5 g 24k, making 150, profit 96 + 75 = 171
  expect(await cells('بضاعة خرجت للتجار حسب العيار', /^18/)).toEqual(['18', '10.000', '10.000', '7.500', '150.00', '171.00']);
  expect(await cells('صافي ربح المبيعات', 'صافي ربح كل المبيعات')).toEqual(['صافي ربح كل المبيعات', '496.00']);
  // stock: 100 g pieces + 20 g scrap = 120 g 18k → 90 g 24k
  expect(await cells('رصيد الذهب الآن حسب العيار', /^18/)).toEqual(['18', '100.000', '20.000', '120.000', '90.000']);
  expect(errs).toEqual([]);
});

test('box filter: sales, goods out to traders and stock now are for that box only', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', vat_rate: 0 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    gold_prices: [{ store_id: STORE, karat: 24, price_per_gram: 120 }],
    invoices: [{ id: 'i1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', total_amount: 1300, created_at: T, created_by: STAFF },
               { id: 'i2', store_id: STORE, invoice_number: 'PINV-1', type: 'buyRetail', status: 'paid', total_amount: 500, created_at: T }],
    invoice_items: [
      { id: 'l1', invoice_id: 'i1', karat: 18, weight_grams: 10, accounting_weight_grams: 9, line_total: 1000, gold_price_per_gram: 80, piece: { cost_fabrication_per_gram: 5, box_name: 'Mirruba' }, lot: null, diamond: null },
      { id: 'l2', invoice_id: 'i1', karat: 21, weight_grams: 2, accounting_weight_grams: 2, line_total: 300, gold_price_per_gram: 100, piece: { cost_fabrication_per_gram: 5, box_name: 'قطع ذهبية' }, lot: null, diamond: null },
      { id: 'l3', invoice_id: 'i2', karat: 18, weight_grams: 6, line_total: 500 }],
    trader_movements: [{ id: 'm1', store_id: STORE, source: 'stock_given', batch_id: 'b1', weight_grams: 10, accounting_weight_grams: 10, piece_acc_weight: 9,
      gold_price_24k: 100, karat: 18, gold_24k_equivalent: 7.5, fab_fee_per_gram: 15, fab_fee_amount: 150, created_at: T,
      trader: { name: 'جليل' }, piece: { barcode: '000001', cost_fabrication_per_gram: 6, accounting_weight_grams: 9, weight_grams: 10, box_name: 'قطع ذهبية' } }],
    pieces: [{ store_id: STORE, status: 'available', karat: 18, weight_grams: 100, box_name: 'Mirruba' },
             { store_id: STORE, status: 'available', karat: 18, weight_grams: 500, box_name: 'قطع ذهبية' }],
    gold_stock_lots: [{ store_id: STORE, karat: 18, weight_grams_remaining: 20, box_name: 'كسر 18' }],
    diamond_pieces: [], expense_entries: [{ store_id: STORE, amount: 50, created_at: T }], customer_debts: [],
  } });
  await page.goto('/profit-report-ar.html');
  await page.waitForFunction(() => [...document.querySelectorAll('#box-filter option')].some(o => o.value === 'Mirruba'));
  await page.selectOption('#box-filter', 'Mirruba');
  await page.fill('#date-from', '2026-09-01');
  await page.fill('#date-to', '2026-09-30');
  await page.click('#apply-filters-btn');
  const br = page.locator('#pr-brief');
  const sec = t => br.locator('div.gm-keep', { hasText: t });
  await expect(br).toContainText('الصندوق: Mirruba');
  expect(await sec('مبيعات الزبائن حسب العيار').locator('tr', { hasText: 'المجموع' }).locator('td').allInnerTexts())
    .toEqual(['المجموع', '10.000', '9.000', '6.750', '1000.00', '235.00']);
  await expect(sec('بضاعة خرجت للتجار حسب العيار')).toContainText('لا يوجد');           // nothing given from Mirruba
  expect(await sec('رصيد الذهب الآن حسب العيار').locator('tr', { hasText: /^18/ }).first().locator('td').allInnerTexts())
    .toEqual(['18', '100.000', '0.000', '100.000', '75.000']);                          // only Mirruba's pieces, no scrap box
  await expect(br.locator('tr', { hasText: 'صافي ربح الصندوق' })).toContainText('235.00'); // no expenses, no scrap
  await expect(br.locator('tr', { hasText: 'المصاريف' })).toHaveCount(0);
  await expect(br.locator('tr', { hasText: 'مشتريات الكسر' })).toHaveCount(0);
  expect(errs).toEqual([]);
});
