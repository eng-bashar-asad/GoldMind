// A typed gold line (no barcode) takes its weight from the chosen box, oldest lot first,
// one stock line per lot, and its price is split by weight.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const lot = (id, grams, t) => ({ id, store_id: STORE, karat: 18, box_name: 'كسر 18', weight_grams_total: grams, weight_grams_remaining: grams, cost_fabrication_per_gram: 0, created_at: t });
const db = () => ({
  stores: [{ id: STORE, currency: 'USD', diamonds_enabled: false, last_gold_ounce_price: 4000, last_gold_ounce_rate: 1, name: 'محل تجربة' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'زبون', phone: '0500000000' }],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 96.5, mode: 'manual_ounce' }],
  pieces: [], diamond_pieces: [], customer_debts: [],
  gold_stock_lots: [lot('L1', 3, '2026-01-01T00:00:00Z'), lot('L2', 4, '2026-01-02T00:00:00Z')], // the query orders by created_at; the fake backend keeps this order
});

test('typed line from the scrap box: 5 g = 3 g from the oldest lot + 2 g from the next, price split by weight', async ({ page }) => {
  const posted = [];
  await install(page, { db: db(), rpc: {
    customer_credit: () => ({ body: 0 }),
    post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-1', invoice_number: 'INV-1' } }; }
  } });
  page.on('dialog', d => d.accept());
  await page.goto('/new-sale-ar.html');
  await page.click('#sale-tabs [data-tab="manual"]');
  await page.fill('#manual-weight', '5');
  await page.fill('#manual-price', '1000');
  await page.locator('button[onclick="addManualToCart()"]').click();
  await expect(page.locator('#manual-source')).toHaveClass(/border-error/);
  await page.selectOption('#manual-source', 'scrap');
  await page.fill('#manual-weight', '5');
  await page.fill('#manual-price', '1000');
  await page.locator('button[onclick="addManualToCart()"]').click();
  await expect(page.locator('#cart-body tr')).toHaveCount(2);
  await page.fill('#customer-search', 'زبون');
  await page.click('#customer-results >> text=زبون');
  await page.click('#save-invoice-btn');
  await expect.poll(() => posted.length).toBe(1);
  const items = posted[0].items;
  expect(items.map(i => i.lot_id)).toEqual(['L1', 'L2']);
  expect(items.map(i => i.weight)).toEqual([3, 2]);
  expect(items.map(i => i.price)).toEqual([600, 400]);
});

test('typed line with stock off: no box needed, no lot is taken', async ({ page }) => {
  const posted = [];
  await install(page, { db: db(), rpc: {
    customer_credit: () => ({ body: 0 }),
    post_sale_invoice: ({ p }) => { posted.push(p); return { body: { id: 'inv-2', invoice_number: 'INV-2' } }; }
  } });
  page.on('dialog', d => d.accept());
  await page.goto('/new-sale-ar.html');
  await page.click('#sale-tabs [data-tab="manual"]');
  await page.uncheck('#manual-from-stock');
  await expect(page.locator('#manual-source-wrap')).toHaveClass(/\bhidden\b/);
  await page.fill('#manual-weight', '5');
  await page.fill('#manual-price', '1000');
  await page.locator('button[onclick="addManualToCart()"]').click();
  await expect(page.locator('#cart-body tr')).toHaveCount(1);
  await page.fill('#customer-search', 'زبون');
  await page.click('#customer-results >> text=زبون');
  await page.click('#save-invoice-btn');
  await expect.poll(() => posted.length).toBe(1);
  expect(posted[0].items[0].lot_id).toBeFalsy();
  expect(posted[0].items[0].weight).toBe(5);
});
