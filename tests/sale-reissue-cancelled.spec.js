// A cancelled sale can be re-issued under its own number: new pieces, customer and date.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  stores: [{ id: STORE, currency: 'USD', diamonds_enabled: false, last_gold_ounce_price: 4000, last_gold_ounce_rate: 1, fab_rate_retail: null, name: 'محل تجربة' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  pieces: [{ id: 'p1', store_id: STORE, barcode: 'GM-0001', karat: 18, weight_grams: 10, accounting_weight_grams: 10, status: 'available', description_ar: 'خاتم' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'راما مملوك', phone: '0501111111' }, { id: 'c2', store_id: STORE, name: 'هلا', phone: '0502222222' }],
  invoices: [{ id: 'old', store_id: STORE, invoice_number: 'INV-2026-000072', type: 'sale', status: 'cancelled', customer_id: 'c1', total_amount: 900, created_at: '2026-10-20T06:00:00Z',
    customer: { id: 'c1', name: 'راما مملوك', phone: '0501111111' }, items: [{ barcode: 'GM-0009', description: 'سلسال' }] }],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 96.5, mode: 'manual_ounce' }],
  diamond_pieces: [], gold_stock_lots: [],
});

test('re-issue: same number, chosen date and customer are sent with the new pieces', async ({ page }) => {
  const posted = [];
  await install(page, { db: db(), rpc: {
    customer_credit: () => ({ body: 0 }),
    post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-new', invoice_number: 'INV-2026-000072' } }; }
  } });
  page.on('dialog', d => d.accept());
  await page.goto('/new-sale-ar.html?reuse=old&draft=none');
  await expect(page.locator('#edit-banner')).toContainText('INV-2026-000072');
  await expect(page.locator('#edit-banner')).toContainText('GM-0009');
  await page.fill('#reuse-date', '2026-10-21T11:30');
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  await page.fill('#barcode-price-input', '1500');
  await page.press('#barcode-price-input', 'Enter');
  await page.fill('#customer-search', 'هلا');
  await page.click('#customer-results >> text=هلا');
  await page.click('#save-invoice-btn');
  await expect.poll(() => posted.length).toBe(1);
  expect(posted[0]).toMatchObject({ reuse_invoice_id: 'old', customer_id: 'c2' });
  expect(new Date(posted[0].sold_at).getTime()).toBe(new Date('2026-10-21T11:30').getTime());
});

test('a future date is refused', async ({ page }) => {
  const posted = [];
  await install(page, { db: db(), rpc: { customer_credit: () => ({ body: 0 }), post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'x', invoice_number: 'x' } }; } } });
  page.on('dialog', d => d.accept());
  await page.goto('/new-sale-ar.html?reuse=old&draft=none');
  await expect(page.locator('#reuse-date')).toBeVisible();
  await page.fill('#reuse-date', '2099-01-01T10:00');
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  await page.fill('#barcode-price-input', '1500');
  await page.press('#barcode-price-input', 'Enter');
  await page.click('#save-invoice-btn');
  await expect(page.locator('body')).toContainText('ليس في المستقبل');
  expect(posted.length).toBe(0);
});

test('cancelled sale page offers «إعادة إصدار بنفس الرقم»', async ({ page }) => {
  await install(page, { generic: true, db: { ...db(), invoices: [{ id: 'old', store_id: STORE, invoice_number: 'INV-2026-000072', type: 'sale', status: 'cancelled', customer_id: 'c1', total_amount: 900, payment_method: 'cash', created_at: '2026-10-20T06:00:00Z' }], invoice_items: [] } });
  await page.goto('/invoice-print-ar.html?id=old');
  const btn = page.locator('#banner-reissue-btn');
  await expect(btn).toBeVisible();
  await expect(btn).toHaveAttribute('href', /new-sale-ar\.html\?reuse=old/);
});
