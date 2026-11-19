// A new give-out voucher starts on gross weight; accounting is opt-in. The per-gram column follows the billed weight.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = (movs) => ({
  stores: [{ id: STORE, name: 'x', currency: 'AED' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
  trader_movements: movs,
  pieces: [{ id: 'pc1', store_id: STORE, barcode: '000709', status: 'available', karat: 18, weight_grams: 10, accounting_weight_grams: 9, cost_fabrication_per_gram: 5 }],
});

test('give-out defaults to gross weight', async ({ page }) => {
  await install(page, { generic: true, db: db([]) });
  await page.goto('/ledger-ar.html?trader=t1&action=give');
  await page.waitForFunction(() => typeof toggleGiveStockForm === 'function' && currentTraderId === 't1');
  await page.evaluate(() => { if (document.getElementById('give-stock-form').classList.contains('hidden')) toggleGiveStockForm(); });
  await page.locator('#gs-barcode-input').fill('000709');
  await page.evaluate(() => searchGiveStockBarcode());
  await expect(page.locator('#gs-cart-list')).toContainText('000709');
  await expect(page.locator('#gs-basis button[data-v=gross]')).toHaveAttribute('style', /background/);
  await expect.poll(async () => parseFloat(await page.locator('#gs-preview-gold').innerText())).toBeCloseTo(10 * 18 / 24, 2);
});

test('per-gram column divides by the billed (gross) weight', async ({ page }) => {
  await install(page, { generic: true, db: db([{ id: 'm1', store_id: STORE, trader_id: 't1', piece_id: 'pc1', movement_type: 'debt_decrease',
    source: 'stock_given', karat: 18, weight_grams: 10, accounting_weight_grams: 9, gold_24k_equivalent: 7.5,
    fab_fee_per_gram: 15, fab_fee_amount: 150, created_at: '2026-11-19T10:00:00Z' }]) });
  await page.goto('/ledger-ar.html?trader=t1');
  await expect(page.locator('td[data-l="متوسط مصنعية الجرام"]').first()).toHaveText(/^15(\.00)?\b/); // 150 ÷ gross 10, not ÷ accounting 9 (16.67)
});
