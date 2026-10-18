// Weights of a gold piece can be corrected on the sale, only with the edit_sale_weights permission.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = perms => ({
  stores: [{ id: STORE, currency: 'USD', diamonds_enabled: false, last_gold_ounce_price: 4000, last_gold_ounce_rate: 1, fab_rate_retail: null, name: 'محل تجربة' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'staff', permissions: perms, full_name: 'موظف' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  pieces: [{ id: 'p1', store_id: STORE, barcode: 'GM-0001', karat: 18, weight_grams: 10, accounting_weight_grams: 9.5, status: 'available', description_ar: 'اسوارة' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'أحمد خالد', phone: '0501111111' }],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 96.5, mode: 'manual_ounce' }],
  diamond_pieces: [], gold_stock_lots: [],
});

async function addPiece(page) {
  await page.goto('/new-sale-ar.html?draft=none');
  await page.fill('#barcode-search-input', 'GM-0001');
  await page.click('button[onclick="searchByBarcode()"]');
  await page.fill('#barcode-price-input', '1500');
  await page.press('#barcode-price-input', 'Enter');
}

test('with the permission: the sale line weight can be corrected (standing and accounting)', async ({ page }) => {
  await install(page, { db: db({ create_invoice: true, edit_sale_weights: true }) });
  await addPiece(page);
  await page.click('button[aria-label^="تعديل وزن القطعة"]');
  await page.locator('input[aria-label="الوزن القائم (غ)"]').fill('9.2');
  await page.locator('input[aria-label="الوزن المحاسبي (غ)"]').fill('8.8');
  await page.keyboard.press('Enter');
  const line = await page.evaluate(() => cart[0]);
  expect(line).toMatchObject({ weight: 9.2, accountingWeight: 8.8, weightChanged: true });
});

test('without the permission: the weight is shown and cannot be changed', async ({ page }) => {
  await install(page, { db: db({ create_invoice: true }) });
  await addPiece(page);
  await expect(page.locator('button[aria-label^="تعديل وزن القطعة"]')).toHaveCount(0);
});
