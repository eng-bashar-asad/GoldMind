// Picking a customer who still owes money (here or in another branch) warns the seller.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = debts => ({
  stores: [{ id: STORE, currency: 'AED', diamonds_enabled: false, last_gold_ounce_price: 4000, last_gold_ounce_rate: 1, name: 'محل' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'راما مملوك', phone: '0501111111' }],
  customer_debts: debts,
  gold_prices: [], pieces: [], diamond_pieces: [], gold_stock_lots: [],
});
async function pick(page, debts) {
  await install(page, { db: db(debts), rpc: { customer_credit: () => ({ body: 0 }) } });
  await page.goto('/new-sale-ar.html?draft=none');
  await page.fill('#customer-search', 'راما');
  await page.click('#customer-results >> text=راما مملوك');
}

test('debt in another branch: the alert shows the total and the part owed elsewhere', async ({ page }) => {
  await pick(page, [
    { customer_id: 'c1', store_id: 'branch-b', movement_type: 'debt_increase', cash_amount: 1000, created_at: '2026-09-01T10:00:00Z' },
    { customer_id: 'c1', store_id: 'branch-b', movement_type: 'debt_decrease', cash_amount: 400, created_at: '2026-09-10T10:00:00Z' },
    { customer_id: 'c1', store_id: STORE, movement_type: 'debt_increase', cash_amount: 250, created_at: '2026-10-01T10:00:00Z' },
  ]);
  const alert = page.locator('#customer-debt-alert');
  await expect(alert).not.toHaveClass(/\bhidden\b/);
  await expect(alert).toContainText('850.00');
  await expect(alert).toContainText('600.00');
  await expect(alert).toContainText('فرع آخر');
});

test('no debt: no alert', async ({ page }) => {
  await pick(page, [
    { customer_id: 'c1', store_id: STORE, movement_type: 'debt_increase', cash_amount: 300, created_at: '2026-09-01T10:00:00Z' },
    { customer_id: 'c1', store_id: STORE, movement_type: 'debt_decrease', cash_amount: 300, created_at: '2026-09-02T10:00:00Z' },
  ]);
  await expect(page.locator('#customer-selected')).not.toHaveClass(/\bhidden\b/);
  await page.waitForTimeout(300);
  await expect(page.locator('#customer-debt-alert')).toHaveClass(/\bhidden\b/);
});
