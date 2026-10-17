// Photographing a trader's invoice fills the receive-goods voucher (lines, reference, VAT); nothing is saved.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const path = require('path'), fs = require('fs'), os = require('os');

test('scan fills receive-goods lines for review', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }], trader_movements: [], invoices: [],
  } });
  let sent = null;
  await page.route('**/functions/v1/extract-invoice-ocr', async r => {
    sent = JSON.parse(r.request().postData());
    await r.fulfill({ contentType: 'application/json', body: JSON.stringify({ extracted: {
      trader_name: 'شركة النور', invoice_number: 'SAL-55', vat_rate: 5, confidence_note: '',
      items: [{ description: 'خواتم', karat: 750, quantity: 3, gross_weight_grams: 12.5, net_weight_grams: 12, fab_fee_per_gram: 8 },
              { description: 'سلسلة', karat: 21, gross_weight_grams: 20, fab_fee_total: 100 }] } }) });
  });
  await page.goto('/ledger-ar.html?trader=t1');
  await page.evaluate(() => toggleReceiveStockForm());
  // a tiny real image file
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  const f = path.join(os.tmpdir(), 'inv-scan.png'); fs.writeFileSync(f, png);
  await page.setInputFiles('#rs-scan-input', f);
  await expect(page.locator('#rs-scan-note')).toContainText('تمت قراءة 2 سطر');
  await expect(page.locator('#rs-scan-note')).toContainText('شركة النور');          // different trader name warned
  expect(sent.mime_type).toBe('image/jpeg');
  const lines = await page.evaluate(() => receiveStockLines.map(l => [l.karat, l.grossWeight, l.accountingWeight, l.fabPerGram, l.description]));
  expect(lines).toEqual([[18, 12.5, 12, 8, 'خواتم (3 قطع)'], [21, 20, 0, 5, 'سلسلة']]);
  await expect(page.locator('#rs-batch-ref')).toHaveValue('SAL-55');
  await expect(page.locator('#rs-vat-rate')).toHaveValue('5');
  expect(calls.some(c => c.method === 'POST' && c.name === 'trader_movements')).toBe(false); // nothing saved
  expect(errs).toEqual([]);
});
