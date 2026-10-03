// The sale screen end to end: scan a piece, pick a customer, save.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  stores: [{ id: STORE, currency: 'USD', diamonds_enabled: false, last_gold_ounce_price: 4000, last_gold_ounce_rate: 1, fab_rate_retail: null, name: 'محل تجربة' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  pieces: [{ id: 'p1', store_id: STORE, barcode: 'GM-0001', karat: 18, weight_grams: 10, accounting_weight_grams: 10, status: 'available', description_ar: 'خاتم' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'أحمد خالد', phone: '0501111111' }],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 96.5, mode: 'manual_ounce' }, { store_id: STORE, karat: 24, price_per_gram: 128.6, mode: 'manual_ounce' }],
  diamond_pieces: [], gold_stock_lots: [],
});

async function fillSale(page, { open = true } = {}) {
  if (open) await page.goto('/new-sale-ar.html');
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  await page.fill('#barcode-price-input', '1500');
  await page.press('#barcode-price-input', 'Enter');
  await page.fill('#customer-search', 'أحمد');
  await page.click('#customer-results >> text=أحمد خالد');
}

test('online sale is posted in one step and opens the print page', async ({ page }) => {
  const posted = [];
  await install(page, { db: db(), rpc: { post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-1', invoice_number: 'INV-2026-000001' } }; } } });
  page.on('dialog', d => d.accept());
  await fillSale(page);
  await page.click('#save-invoice-btn');
  await page.waitForURL(/invoice-print-ar\.html\?id=inv-1/);
  expect(posted).toHaveLength(1);
  expect(posted[0]).toMatchObject({ store_id: STORE, customer_id: 'c1', payment_method: 'cash' });
  expect(posted[0].items).toEqual([expect.objectContaining({ piece_id: 'p1', price: 1500 })]);
  expect(posted[0].client_ref).toBeTruthy();
});

test('sale without internet is kept on the device and posted later', async ({ page, context }) => {
  const posted = [];
  await install(page, { db: db(), rpc: { post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-2', invoice_number: 'INV-2026-000002' } }; } } });
  page.on('dialog', d => d.accept());
  await page.goto('/new-sale-ar.html');
  await page.waitForFunction(() => localStorage.getItem('gm_snapshot_at'));   // on-device copy ready
  page.__gmNet.offline = true;
  await context.setOffline(true);
  await fillSale(page, { open: false });
  await page.click('#save-invoice-btn');
  await expect(page.locator('#save-message')).toContainText('حُفظت الفاتورة على الجهاز');
  await expect(page.locator('#gm-offline-badge')).toContainText('1 فاتورة بانتظار الترحيل');
  expect(posted).toHaveLength(0);

  page.__gmNet.offline = false;
  await context.setOffline(false);
  await expect.poll(() => posted.length, { timeout: 10000 }).toBe(1);
  await expect(page.locator('#gm-offline-badge')).toHaveCount(0);
  expect(posted[0].items[0].piece_id).toBe('p1');
});

test('offline: a brand-new customer can be added and goes with the sale', async ({ page, context }) => {
  const posted = [];
  await install(page, { db: db(), rpc: { post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-3', invoice_number: 'INV-3' } }; } } });
  await page.goto('/new-sale-ar.html');
  await page.waitForFunction(() => localStorage.getItem('gm_snapshot_at'));
  page.__gmNet.offline = true;
  await context.setOffline(true);
  const answers = ['سامر', '0509999999'];
  page.on('dialog', d => d.type() === 'prompt' ? d.accept(answers.shift()) : d.accept());
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  await page.fill('#barcode-price-input', '1500');
  await page.press('#barcode-price-input', 'Enter');
  await page.click('button[onclick="addNewCustomer()"]');
  await expect(page.locator('#customer-selected-name')).toHaveText('سامر');
  await page.click('#save-invoice-btn');
  await expect(page.locator('#save-message')).toContainText('حُفظت الفاتورة على الجهاز');
  page.__gmNet.offline = false;
  await context.setOffline(false);
  await expect.poll(() => posted.length, { timeout: 10000 }).toBe(1);
  expect(posted[0].customer_id).toBeNull();
  expect(posted[0].new_customer).toEqual({ name: 'سامر', phone: '0509999999' });
});

test('price of a line can be changed before posting (tap the price)', async ({ page }) => {
  const posted = [];
  await install(page, { db: db(), rpc: { post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-9', invoice_number: 'INV-2026-000009' } }; } } });
  page.on('dialog', d => d.accept());
  await fillSale(page);
  await page.click('#cart-body button[aria-label^="تعديل سعر القطعة"]');
  const input = page.locator('#cart-body input[aria-label="السعر الجديد"]');
  await input.fill('1800');
  await input.press('Enter');
  await expect(page.locator('#grand-total')).toContainText('1,800.00');
  await expect(page.locator('#grand-weight')).toHaveText('10.00 غ');
  // invalid value on leaving the field keeps the previous price
  await page.click('#cart-body button[aria-label^="تعديل سعر القطعة"]');
  await input.fill('0');
  await page.locator('#grand-total').click();
  await expect(page.locator('#grand-total')).toContainText('1,800.00');
  await page.click('#save-invoice-btn');
  await page.waitForURL(/invoice-print-ar\.html\?id=inv-9/);
  expect(posted[0].items[0].price).toBe(1800);
});

test('camera scan fills the barcode and finds the piece', async ({ page }) => {
  await install(page, { db: db() });
  // fake camera library: decodes one barcode as soon as it starts
  await page.addInitScript(() => {
    window.Html5QrcodeSupportedFormats = { CODE_128: 1, CODE_39: 2, EAN_13: 3, QR_CODE: 4 };
    window.Html5Qrcode = class { start(_c, _o, ok) { setTimeout(() => ok('GM-0001'), 50); return Promise.resolve(); } stop() { return Promise.resolve(); } clear() {} };
  });
  await page.goto('/new-sale-ar.html');
  await page.click('button[onclick="openSaleScanner()"]');
  await expect(page.locator('#barcode-search-input')).toHaveValue('GM-0001');
  await expect(page.locator('#barcode-price-input')).toBeVisible();
  await expect(page.locator('#sale-scan-box')).toHaveClass(/hidden/);
});
