// Financial report: net profit counts goods given to wholesale traders too (same as the profit report).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('net profit = customers + wholesale traders + scrap − expenses', async ({ page }) => {
  const now = new Date().toISOString();
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD', vat_rate: 0 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [], invoice_items: [], customer_debts: [], daily_cash_log: [], pieces: [], gold_stock_lots: [], customer_deposits: [],
    gold_prices: [{ store_id: STORE, karat: 24, price_per_gram: 120 }],
    expense_entries: [{ store_id: STORE, amount: 21, description: 'قهوة', created_at: now }],
    trader_movements: [{ id: 'g1', store_id: STORE, source: 'stock_given', movement_type: 'debt_decrease', karat: 18, gold_24k_equivalent: 7.5,
      piece_acc_weight: 9, fab_fee_per_gram: 15, gold_price_24k: 100, fab_fee_amount: 150, piece: { cost_fabrication_per_gram: 6 }, created_at: now }],
  } });
  await page.goto('/financial-report-ar.html');
  const body = page.locator('body');
  await expect(body).toContainText('ربح البضاعة الخارجة لتجار الجملة');
  await expect(body).toContainText('171.00');                                  // 96 making + 75 gold difference
  await expect(body).toContainText('150.00');                                  // 171 − 21 expenses
});
