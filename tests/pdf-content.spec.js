// The invoice PDF must contain the invoice, even when the page is scrolled down.
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const LIB_PATH = path.join(__dirname, 'node_modules/html2pdf.js/dist/html2pdf.bundle.min.js');
const H2C_PATH = path.join(__dirname, 'node_modules/html2canvas/dist/html2canvas.min.js');
test.skip(!fs.existsSync(LIB_PATH) || !fs.existsSync(H2C_PATH), 'PDF libraries not installed');

test('invoice PDF is not blank (page scrolled down)', async ({ page }) => {
  const items = Array.from({ length: 7 }, (_, i) => ({ id: 'it' + i, invoice_id: 'inv-1', store_id: STORE, description: 'إسوارة', description_en: 'Bracelet', karat: 18, weight_grams: 25.5, price: 3300, piece_id: null }));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'Ahmad Al Khayat', currency: 'USD', vat_rate: 1, address: 'دمشق', phone: '+963' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Bashar' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [{ id: 'inv-1', store_id: STORE, invoice_number: 'INV-2026-000001', invoice_type: 'sale', total_amount: 23100, subtotal: 22871.29, vat_amount: 228.71, created_at: '2026-09-27T14:11:09Z', payment_method: 'cash', customer_id: 'c1', staff_id: STAFF, status: 'posted' }],
    invoice_items: items, customers: [{ id: 'c1', store_id: STORE, name: 'رزان الحلبي' }],
    pieces: [], traders: [], gold_prices: [],
  } });
  await page.route(/html2pdf/, (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(LIB_PATH, 'utf8') }));
  await page.route(/html2canvas/, (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(H2C_PATH, 'utf8') }));
  await page.setViewportSize({ width: 390, height: 800 });
  await page.goto('/invoice-print-ar.html?id=inv-1');
  await expect(page.locator('#inv-number')).toContainText('INV-2026-000001');
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  // Capture what would go into the PDF instead of downloading it.
  await page.evaluate(() => {
    window.gmSavePdf = async (worker) => {
      const canvas = await worker.get('canvas');
      const d = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
      let dark = 0, rightDark = 0; const w = canvas.width;
      for (let i = 0; i < d.length; i += 4) if (d[i] < 120) { dark++; if (((i / 4) % w) > w * 0.85) rightDark++; }
      window.__pdf = { w: canvas.width, h: canvas.height, dark, rightDark };
    };
  });
  await page.click('#download-pdf-btn');
  await expect.poll(() => page.evaluate(() => window.__pdf), { timeout: 20000 }).toBeTruthy();
  const pdf = await page.evaluate(() => window.__pdf);
  expect(pdf.h).toBeGreaterThan(500);
  expect(pdf.dark).toBeGreaterThan(5000); // real text and table lines, not a white page
  expect(pdf.rightDark).toBeGreaterThan(500); // the Arabic (right) side is on the page, not cut off
});
