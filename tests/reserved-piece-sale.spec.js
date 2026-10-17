// A piece held by a deposit is sellable only to the customer who put it on deposit.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  stores: [{ id: STORE, currency: 'USD', diamonds_enabled: false, last_gold_ounce_price: 4000, last_gold_ounce_rate: 1, fab_rate_retail: null, name: 'محل تجربة' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  pieces: [{ id: 'p1', store_id: STORE, barcode: 'GM-0001', karat: 18, weight_grams: 10, accounting_weight_grams: 10, status: 'reserved', reserved_customer_id: 'c1', description_ar: 'خاتم' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'أحمد خالد', phone: '0501111111' }],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 96.5, mode: 'manual_ounce' }],
  diamond_pieces: [], gold_stock_lots: [],
});

test('reserved piece: the barcode search lets the depositor buy it, others never see it', async ({ page }) => {
  const calls = await install(page, { db: db() });
  await page.goto('/new-sale-ar.html');
  await page.evaluate(() => pickCustomer({ id: 'c1', name: 'أحمد خالد', phone: '0501111111' }));
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  const find = () => calls.find(c => c.url.includes('/pieces') && c.url.includes('or='));
  await expect.poll(() => !!find()).toBe(true);
  const q = decodeURIComponent(find().url);
  expect(q).toContain('status.eq.available,and(status.eq.reserved,reserved_customer_id.eq.c1)');
});
