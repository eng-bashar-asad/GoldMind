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

test('edit an invoice with a piece line: the weight can be corrected (the page answers permissions after the lines are drawn)', async ({ page }) => {
  page.on('dialog', d => d.accept().catch(() => {}));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'staff', permissions: { create_invoice: true, edit_invoice: true, edit_sale_weights: true }, full_name: 'موظف' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [{ id: 'inv1', store_id: STORE, invoice_number: 'INV-40', type: 'sale', customer_id: 'c1', total_amount: 1000, amount_paid: 1000, payment_method: 'cash', created_at: '2026-10-11T07:00:00Z',
      customer: { id: 'c1', name: 'رجاء', phone: '050' },
      items: [{ id: 'it1', piece_id: 'p1', barcode: 'GM-0001', karat: 18, weight_grams: 10, accounting_weight_grams: 9.5, line_total: 1000, description: 'اسوارة' }] }],
    customers: [{ id: 'c1', store_id: STORE, name: 'رجاء', phone: '050' }],
    customer_debts: [], gold_prices: [], gold_stock_lots: [], pieces: [], diamond_pieces: []
  } });
  await page.goto('/new-sale-ar.html?edit=inv1');
  await expect(page.locator('#edit-banner')).toContainText('INV-40');
  await expect(page.locator('button[aria-label^="تعديل وزن القطعة"]')).toHaveCount(1);
});
