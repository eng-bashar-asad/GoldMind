// Customer statement: invoices by date with their pieces, cash debts, payments,
// deposits; one running balance; PDF sent on WhatsApp with welcome/thanks text.
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const LIB = path.join(__dirname, 'node_modules/html2pdf.js/dist/html2pdf.bundle.min.js');
const H2C = path.join(__dirname, 'node_modules/html2canvas/dist/html2canvas.min.js');

const D = (id, type, amt, extra) => ({ id, store_id: STORE, customer_id: 'cu1', movement_type: type, cash_amount: amt, gold_grams_24k: 0, ...extra });
const db = {
  stores: [{ id: STORE, name: 'محل الاختبار', currency: 'USD', country: 'SY', phone: '011' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  customers: [{ id: 'cu1', store_id: STORE, name: 'ريما شالاتي', phone: '0944123456' }],
  invoices: [{ id: 'i5', store_id: STORE, customer_id: 'cu1', invoice_number: 'INV-5', type: 'sale', total_amount: 4100, amount_paid: 4100, status: 'paid', created_at: '2026-09-28T18:45:00Z' }],
  customer_debts: [
    D('d1', 'debt_increase', 3900, { invoice_id: 'i5', created_at: '2026-09-28T18:45:00Z' }),
    D('d2', 'debt_decrease', 3900, { notes: 'دفعة يدوية', source: 'payment', created_at: '2026-09-29T13:26:00Z' }),
    D('d3', 'debt_decrease', 3900, { invoice_id: 'i5', source: 'allocation', created_at: '2026-09-29T13:26:00Z' }),
    D('d4', 'debt_increase', 3900, { source: 'allocation', created_at: '2026-09-29T13:26:00Z' }),
    D('d5', 'debt_decrease', 200, { notes: 'عربون DEP-000001', source: 'deposit', created_at: '2026-09-30T10:00:00Z' }),
  ],
  invoice_items: [{ invoice_id: 'i5', description: 'طقم ذهب', barcode: '000123', karat: 18, weight_grams: 25.5, line_total: 4100 }],
};

test('statement: running balance, invoice pieces, WhatsApp PDF', async ({ page }) => {
  test.skip(!fs.existsSync(LIB) || !fs.existsSync(H2C), 'PDF libraries not installed');
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db });
  await page.route(/html2pdf/, r => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(LIB, 'utf8') }));
  await page.route(/html2canvas/, r => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(H2C, 'utf8') }));
  await page.addInitScript(() => { window.open = u => { window.__opened = u; }; window.alert = m => { window.__alert = m; }; });
  await page.goto('/customer-debts-print-ar.html?id=cu1');
  const rows = page.locator('#rows > tr:not(.items-row)');
  await expect(rows).toHaveCount(3);
  await expect(rows.nth(0)).toContainText('فاتورة بيع INV-5');
  await expect(rows.nth(0)).toContainText('4,100.00');
  await expect(rows.nth(0).locator('td').nth(3)).toHaveText('200.00');     // paid at the counter
  await expect(rows.nth(0).locator('td').nth(4)).toHaveText('3,900.00');
  await expect(rows.nth(1)).toContainText('دفعة من العميل');
  await expect(rows.nth(1).locator('td').nth(4)).toHaveText('0.00');
  await expect(rows.nth(2)).toContainText('عربون DEP-000001');
  await expect(page.locator('#bal-label')).toHaveText('رصيد للعميل لدى المحل');
  await expect(page.locator('#bal-value')).toContainText('200.00');
  await rows.nth(0).click();
  await expect(page.locator('#items-i5')).toContainText('طقم ذهب');
  await expect(page.locator('#items-i5')).toContainText('25.50 غ');

  // period filter: payments before the start become the opening balance
  await page.fill('#from', '2026-09-29');
  await page.click('button:has-text("عرض")');
  await expect(page.locator('#rows > tr').first()).toContainText('رصيد سابق حتى بداية الفترة');
  await expect(page.locator('#rows > tr').first()).toContainText('3,900.00');

  await page.evaluate(() => { window.__pdf = null; const orig = window.gmSavePdf; window.gmSavePdf = async (w, n, t, text) => { window.__pdf = { n, text }; return 'downloaded'; }; });
  await page.click('#wa-btn');
  await page.waitForFunction(() => window.__opened, null, { timeout: 20000 });
  const pdf = await page.evaluate(() => window.__pdf);
  expect(pdf.text).toContain('مرحباً ريما شالاتي');
  expect(pdf.text).toContain('شكراً لتعاملكم معنا');
  expect(await page.evaluate(() => window.__opened)).toContain('https://wa.me/963944123456?text=');
  expect(errs).toEqual([]);
});
