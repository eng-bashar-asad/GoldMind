// Profit report and financial report: printable, PDF has real content, numbers from the shared formula.
const { test, expect } = require('@playwright/test');
const fs = require('fs'), path = require('path');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const LIB = path.join(__dirname, 'node_modules/html2pdf.js/dist/html2pdf.bundle.min.js');
const H2C = path.join(__dirname, 'node_modules/html2canvas/dist/html2canvas.min.js');

const now = new Date().toISOString();
const db = {
  stores: [{ id: STORE, name: 'مجوهرات الاختبار', currency: 'USD', vat_rate: 1 }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  invoices: [
    { id: 'i1', store_id: STORE, invoice_number: 'INV-2026-000001', type: 'sale', status: 'paid', payment_method: 'cash', total_amount: 3600, amount_paid: 3600, created_at: now },
    { id: 'i2', store_id: STORE, invoice_number: 'PINV-2026-000001', type: 'buyRetail', status: 'paid', payment_method: 'cash', total_amount: 1000, amount_paid: 1000, created_at: now },
  ],
  invoice_items: [
    { id: 'l1', invoice_id: 'i1', barcode: 'M A 460 W', karat: 18, weight_grams: 15.03, accounting_weight_grams: 14.24, line_total: 3600, gold_price_per_gram: 103.45, fabrication_fee: 0,
      piece: { cost_fabrication_per_gram: 31.6, accent_diamond_carat: 0.39, accent_diamond_price_per_carat: 500 }, lot: null, diamond: null },
    { id: 'l2', invoice_id: 'i2', karat: 21, weight_grams: 10, accounting_weight_grams: 10, line_total: 1000 },
  ],
  expense_entries: [{ store_id: STORE, amount: 46.24, created_at: now, category: { name: 'ضيافة' } }],
  daily_cash_log: [{ store_id: STORE, direction: 'in', amount: 3600, currency: 'USD', created_at: now }, { store_id: STORE, direction: 'out', amount: 1000, currency: 'USD', created_at: now }],
  customer_debts: [], trader_movements: [], pieces: [], gold_stock_lots: [], gold_prices: [], diamond_pieces: [],
};

async function setup(page) {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db });
  await page.route(/html2pdf/, r => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(LIB, 'utf8') }));
  await page.route(/html2canvas/, r => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(H2C, 'utf8') }));
  await page.addInitScript(() => {
    // capture the PDF instead of downloading it
    window.__capture = function () {
      window.gmSavePdf = async (worker, name) => {
        const pdf = await worker.get('pdf');
        const blob = pdf.output('arraybuffer');
        window.__pdf = { name, pages: pdf.internal.getNumberOfPages(), bytes: blob.byteLength };
      };
    };
  });
  return errs;
}

test('profit report: totals row, print header, PDF', async ({ page }) => {
  test.skip(!fs.existsSync(LIB) || !fs.existsSync(H2C), 'PDF libraries not installed');
  const errs = await setup(page);
  await page.goto('/profit-report-ar.html');
  await expect(page.locator('#items-tbody')).toContainText('المجموع');
  await expect(page.locator('#stat-profit')).toHaveText('1446.24');
  await expect(page.locator('#pr-store')).toHaveText('مجوهرات الاختبار');
  await page.evaluate(() => window.__capture());
  await page.click('#pr-pdf-btn');
  await page.waitForFunction(() => window.__pdf, null, { timeout: 20000 });
  const pdf = await page.evaluate(() => window.__pdf);
  expect(pdf.pages).toBeGreaterThanOrEqual(1);
  expect(pdf.bytes).toBeGreaterThan(20000);
  expect(errs).toEqual([]);
});

test('financial report: today, numbers, PDF', async ({ page }) => {
  test.skip(!fs.existsSync(LIB) || !fs.existsSync(H2C), 'PDF libraries not installed');
  const errs = await setup(page);
  await page.addInitScript(() => localStorage.setItem('gm_fr_period', 'today'));
  await page.goto('/financial-report-ar.html');
  await expect(page.locator('#fr-body')).toContainText('صافي الربح');
  const t = await page.locator('#fr-body').innerText();
  // sale 3600, profit 1446.24 (shared formula), expense 46.24 → net 1400.00; cash 3600 in / 1000 out
  for (const s of ['3,600.00', '1,000.00', '1,446.24', '46.24', '1,400.00', '2,600.00']) expect(t, s).toContain(s);
  await page.evaluate(() => window.__capture());
  await page.click('button:has-text("PDF")');
  await page.waitForFunction(() => window.__pdf, null, { timeout: 20000 });
  const pdf = await page.evaluate(() => window.__pdf);
  expect(pdf.name).toMatch(/^التقرير-المالي-\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}\.pdf$/);
  expect(pdf.bytes).toBeGreaterThan(20000);
  expect(errs).toEqual([]);
});

test('financial report: debts owed to us, owed by us, deposits and their receipts', async ({ page }) => {
  const errs = await setup(page);
  const now = new Date().toISOString();
  const D = (cust, type, amt, source, inv) => ({ store_id: STORE, customer_id: cust, movement_type: type, cash_amount: amt, gold_grams_24k: 0, source, invoice_id: inv || null, created_at: now });
  db.customer_debts = [
    D('rima', 'debt_increase', 3900, null, 'i5'), D('rima', 'debt_decrease', 3900, 'payment'),
    D('rima', 'debt_decrease', 3900, 'allocation', 'i5'), D('rima', 'debt_increase', 3900, 'allocation'),
    D('x', 'debt_increase', 900, null, 'i7'), D('x', 'debt_decrease', 100, 'invoice_edit', 'i7'),
    D('hala', 'debt_decrease', 200, 'deposit'),
    D('y', 'debt_decrease', 50, 'payment') ];
  db.customer_deposits = [{ store_id: STORE, deposit_number: 'DEP-000001', amount: 200, status: 'active', created_at: now, items: [{ description: 'طقم ديور' }], customer: { name: 'هلا الهفل' } }];
  await page.addInitScript(() => localStorage.setItem('gm_fr_period', 'today'));
  await page.goto('/financial-report-ar.html');
  await expect(page.locator('#fr-body')).toContainText('ديون لنا على الزبائن');
  const row = t => page.locator('#fr-body tr', { hasText: t }).first();
  await expect(row('ديون لنا على الزبائن')).toContainText('800.00');
  await expect(row('ديون علينا للزبائن')).toContainText('50.00');
  await expect(row('عربون قائم (1 إيصال)')).toContainText('200.00');
  await expect(row('ديون جديدة على الزبائن')).toContainText('4,700.00');
  await expect(row('دفعات استلمناها من الزبائن')).toContainText('3,950.00');
  await expect(page.locator('#fr-body')).toContainText('إيصالات العربون');
  await expect(row('DEP-000001')).toContainText('طقم ديور');
  expect(errs).toEqual([]);
});
