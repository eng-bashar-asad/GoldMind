// A sale line below cost (gold at today's price + making) is marked red and the invoice is not posted on the first press.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  stores: [{ id: STORE, currency: 'USD', diamonds_enabled: false, last_gold_ounce_price: 4000, last_gold_ounce_rate: 1, fab_rate_retail: null, vat_rate: 0, name: 'محل تجربة' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  // cost = 10 g × 96.5 + 10 g × 10 making = 1065
  pieces: [{ id: 'p1', store_id: STORE, barcode: 'GM-0001', karat: 18, weight_grams: 10.4, accounting_weight_grams: 10, cost_fabrication_per_gram: 10, status: 'available', description_ar: 'خاتم' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'أحمد خالد', phone: '0501111111' }],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 96.5, mode: 'manual_ounce' }],
  diamond_pieces: [], gold_stock_lots: [],
});

async function sell(page, price) {
  await page.goto('/new-sale-ar.html?draft=none');
  await page.waitForFunction(() => __goldPriceByKarat[18] > 0);
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  await page.fill('#barcode-price-input', String(price));
  return page;
}

test('a losing price: red hint while typing, red line, no posting on the first press, posted on the second', async ({ page }) => {
  const posted = [];
  await install(page, { db: db(), rpc: { post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-1', invoice_number: 'INV-1' } }; } } });
  page.on('dialog', d => d.accept());
  await sell(page, 1000);
  await expect(page.locator('#barcode-loss-hint')).toContainText('قيمة خاسرة');
  await expect(page.locator('#barcode-loss-hint')).toContainText('65.00');
  await page.press('#barcode-price-input', 'Enter');
  await expect(page.locator('#cart-body tr.gm-loss-row')).toHaveCount(1);
  await expect(page.locator('#loss-banner')).toContainText('قطعة خاسرة');
  await page.fill('#customer-search', 'أحمد');
  await page.click('#customer-results >> text=أحمد خالد');
  await page.click('#save-invoice-btn');
  await expect(page.locator('#save-message')).toContainText('قيمة خاسرة');
  await page.waitForTimeout(400);
  expect(posted).toHaveLength(0);
  await page.click('#save-invoice-btn');
  await page.waitForURL(/invoice-print-ar\.html\?id=inv-1/);
  expect(posted).toHaveLength(1);
});

test('a price above cost: no warning, posted on the first press', async ({ page }) => {
  const posted = [];
  await install(page, { db: db(), rpc: { post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-2', invoice_number: 'INV-2' } }; } } });
  page.on('dialog', d => d.accept());
  await sell(page, 1100);
  await expect(page.locator('#barcode-loss-hint')).toHaveClass(/hidden/);
  await page.press('#barcode-price-input', 'Enter');
  await expect(page.locator('#cart-body tr.gm-loss-row')).toHaveCount(0);
  await expect(page.locator('#loss-banner')).toHaveClass(/hidden/);
  await page.fill('#customer-search', 'أحمد');
  await page.click('#customer-results >> text=أحمد خالد');
  await page.click('#save-invoice-btn');
  await page.waitForURL(/invoice-print-ar\.html\?id=inv-2/);
  expect(posted).toHaveLength(1);
});
