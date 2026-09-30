// Profit report: retail vs wholesale profit, sold weights/carats/average making,
// scrap purchases and goods in from traders, per-staff table, Excel export.
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const XLSX_LIB = path.join(__dirname, 'node_modules/xlsx/dist/xlsx.full.min.js');

const T = '2026-09-15T10:00:00Z';
const db = {
  stores: [{ id: STORE, name: 'محل', vat_rate: 0 }],
  staff: [
    { id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' },
    { id: 'st2', store_id: STORE, role: 'staff', permissions: {}, full_name: 'صقر' } ],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 100 }],
  pieces: [], diamond_pieces: [],
  invoices: [
    { id: 'i1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', created_by: STAFF, created_at: T },
    { id: 'i2', store_id: STORE, invoice_number: 'INV-2', type: 'sale', status: 'paid', created_by: 'st2', created_at: T },
    { id: 'b1', store_id: STORE, invoice_number: 'BUY-1', type: 'buyRetail', status: 'paid', created_by: STAFF, created_at: T } ],
  invoice_items: [
    // 10 g gross / 9.5 acc, 18K @100 → gold 950; sold 1300 → making sold 350 (36.84/g); our cost 2/g
    { invoice_id: 'i1', barcode: '000001', karat: 18, weight_grams: 10, accounting_weight_grams: 9.5, line_total: 1300, gold_price_per_gram: 100, piece: { cost_fabrication_per_gram: 2 } },
    // diamond piece 0.5 ct
    { invoice_id: 'i2', barcode: 'D1', karat: 18, weight_grams: 0, line_total: 2000, gold_price_per_gram: 100, diamond: { diamond_carat: 0.5, diamond_price_per_carat: 1000, has_gold: false } },
    { invoice_id: 'b1', karat: 21, weight_grams: 20, accounting_weight_grams: 20, line_total: 1600 } ],
  trader_movements: [
    { id: 'm1', store_id: STORE, source: 'stock_given', weight_grams: 100, accounting_weight_grams: 100, karat: 18, fab_fee_per_gram: 10, fab_fee_amount: 1000, created_at: T, trader: { name: 'تاجر أ' }, piece: null },
    { id: 'm2', store_id: STORE, source: 'stock_given', weight_grams: 5, accounting_weight_grams: 5, karat: 18, fab_fee_per_gram: 20, fab_fee_amount: 100, created_at: T, trader: { name: 'تاجر ب' }, piece: { cost_fabrication_per_gram: 8 } },
    { id: 'm3', store_id: STORE, source: 'stock_received', weight_grams: 50, accounting_weight_grams: 48, karat: 18, created_at: T, trader: { name: 'تاجر أ' } } ],
};

test('profit report sections and Excel', async ({ page }) => {
  test.skip(!fs.existsSync(XLSX_LIB), 'xlsx not installed');
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db });
  await page.route(/xlsx\.full/, r => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(XLSX_LIB, 'utf8') }));
  await page.goto('/profit-report-ar.html');
  await page.fill('#date-from', '2026-09-01');
  await page.fill('#date-to', '2026-09-30');
  await page.click('#apply-filters-btn');
  const sec = page.locator('#pr-sections');
  // retail: 1300−950−19 = 331 ; diamond 2000−500 = 1500 → 1831
  await expect(sec.locator('tr', { hasText: 'مبيعات الزبائن' })).toContainText('1831.00');
  // wholesale: 1000 (no cost known) + (100 − 40) = 1060
  await expect(sec.locator('tr', { hasText: 'تجار الجملة' })).toContainText('1060.00');
  await expect(sec.locator('tr', { hasText: 'المجموع' }).first()).toContainText('2891.00');
  await expect(sec).toContainText('1 تسليم بالوزن بدون باركود');
  const w = sec.locator(':scope > div', { hasText: 'المبيع بالوزن' }).locator('tbody tr').first();
  await expect(w).toContainText('10.000 غ');
  await expect(w).toContainText('9.500 غ');
  await expect(w).toContainText('0.50 ct');
  await expect(w).toContainText('36.84');
  await expect(sec.locator(':scope > div', { hasText: 'مشتريات الكسر' })).toContainText('20.000');
  await expect(sec.locator(':scope > div', { hasText: 'بضاعة داخلة من التجار' })).toContainText('48.000');
  const staff = sec.locator(':scope > div', { hasText: 'مبيعات كل موظف' });
  await expect(staff.locator('tbody tr').first()).toContainText('صقر');
  await expect(staff.locator('tbody tr').nth(1)).toContainText('بشار');

  await page.evaluate(async () => { await gmLoadScript('https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js', 'XLSX'); window.XLSX.writeFile = (wb, name) => { window.__wb = { name, sheets: wb.SheetNames, sum: XLSX.utils.sheet_to_json(wb.Sheets['الموظفون'], { header: 1 }), f: wb.Sheets['الجملة']['G4'] }; }; });
  await page.click('#pr-xlsx-btn');
  await page.waitForFunction(() => window.__wb);
  const wb = await page.evaluate(() => window.__wb);
  expect(wb.sheets).toEqual(['الملخص', 'مبيعات المفرق', 'الجملة', 'الموظفون', 'مشتريات الكسر', 'وارد من التجار']);
  expect(wb.f.f).toBe('SUM(G2:G3)');
  expect(wb.sum[0]).toContain('الموظف');
  expect(errs).toEqual([]);
});
