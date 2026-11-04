// A customer's deposit (عربون) pays the sale first: a full cash sale takes only the rest in cash.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  stores: [{ id: STORE, currency: 'USD', diamonds_enabled: false, last_gold_ounce_price: 4000, last_gold_ounce_rate: 1, fab_rate_retail: null, name: 'محل تجربة' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  pieces: [{ id: 'p1', store_id: STORE, barcode: 'GM-0001', karat: 18, weight_grams: 10, accounting_weight_grams: 10, status: 'available', description_ar: 'خاتم' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'راما مملوك', phone: '0501111111' }],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 96.5, mode: 'manual_ounce' }],
  diamond_pieces: [], gold_stock_lots: [],
});

test('customer with a deposit: a full cash sale is paid by the deposit first, the rest in cash', async ({ page }) => {
  const posted = [];
  await install(page, { db: db(), rpc: {
    customer_credit: () => ({ body: 1000 }),
    post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-1', invoice_number: 'INV-1' } }; }
  } });
  page.on('dialog', d => d.accept());
  await page.goto('/new-sale-ar.html?draft=none');
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  await page.fill('#barcode-price-input', '1500');
  await page.press('#barcode-price-input', 'Enter');
  await page.fill('#customer-search', 'راما');
  await page.click('#customer-results >> text=راما مملوك');
  await expect(page.locator('#customer-credit')).toContainText('1,000');
  await page.click('#save-invoice-btn');
  await page.waitForURL(/invoice-print-ar\.html\?id=inv-1/);
  expect(posted[0]).toMatchObject({ payment_method: 'mixed', cash_paid: 500 });
});

test('the deposit is taken off even if the credit had not loaded yet when saving', async ({ page }) => {
  const posted = []; let calls = 0;
  await install(page, { db: db(), rpc: {
    customer_credit: () => ({ body: calls++ === 0 ? 0 : 100 }), // first (on-screen) read is late/empty
    post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-1', invoice_number: 'INV-1' } }; }
  } });
  page.on('dialog', d => d.accept());
  await page.goto('/new-sale-ar.html?draft=none');
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  await page.fill('#barcode-price-input', '1500');
  await page.press('#barcode-price-input', 'Enter');
  await page.fill('#customer-search', 'راما');
  await page.click('#customer-results >> text=راما مملوك');
  await page.click('#save-invoice-btn');
  await page.waitForURL(/invoice-print-ar\.html\?id=inv-1/);
  expect(posted[0]).toMatchObject({ payment_method: 'mixed', cash_paid: 1400 });
});

// a deposit held for another piece: by default the new piece is paid in full in cash and the deposit stays;
// the seller can still take it off the deposit.
for (const choice of ['default', 'use']) test('deposit for another piece — ' + choice, async ({ page }) => {
  const posted = [];
  await install(page, { db: { ...db(), customer_deposits: [{ id: 'd1', store_id: STORE, customer_id: 'c1', deposit_number: 'DEP-000009', status: 'active', amount: 300, items: [{ barcode: 'GM-0009' }] }] }, rpc: {
    customer_credit: () => ({ body: 300 }),
    post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-1', invoice_number: 'INV-1' } }; }
  } });
  page.on('dialog', d => d.accept());
  await page.goto('/new-sale-ar.html?draft=none');
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  await page.fill('#barcode-price-input', '1500');
  await page.press('#barcode-price-input', 'Enter');
  await page.fill('#customer-search', 'راما');
  await page.click('#customer-results >> text=راما مملوك');
  await expect(page.locator('#customer-credit')).toContainText('GM-0009');
  await expect(page.locator('input[name="credit-use"][value="keep"]')).toBeChecked();
  if (choice === 'use') await page.check('input[name="credit-use"][value="use"]');
  await page.click('#save-invoice-btn');
  await page.waitForURL(/invoice-print-ar\.html\?id=inv-1/);
  if (choice === 'use') expect(posted[0]).toMatchObject({ payment_method: 'mixed', cash_paid: 1200 });
  else expect(posted[0]).toMatchObject({ payment_method: 'cash' });
});
