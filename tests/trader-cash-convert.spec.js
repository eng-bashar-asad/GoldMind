// Trader account: pay cash out / receive cash in, and "تسكير عملات" — settle the gold
// balance at a chosen gold price so it becomes cash; statement shows these rows.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const T = '2026-09-30T10:00:00Z';
const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  traders: [{ id: 't1', store_id: STORE, name: 'تاجر أ', phone: '0999' }],
  gold_prices: [{ store_id: STORE, karat: 24, price_per_gram: 110 }, { store_id: STORE, karat: 21, price_per_gram: 96 }],
  cash_movements: [],
  // we received 100 g 24k + 500 making → we owe him gold 100 g and cash 500
  trader_movements: [{ id: 'm1', store_id: STORE, trader_id: 't1', movement_type: 'debt_increase', source: 'stock_received', weight_grams: 100, karat: 24, gold_24k_equivalent: 100, fab_fee_amount: 500, created_at: T }],
});

test('convert gold balance to cash, then pay cash out', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const calls = await install(page, { db: db(), rpc: { trader_gold_to_cash: () => ({ body: 11000 }), trader_cash_move: () => ({ body: 'x' }) } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/ledger-ar.html?trader=t1');
  await page.waitForFunction(() => typeof currentTraderId !== 'undefined' && currentTraderId === 't1');
  await page.click('button:has-text("تسكير عملات")');
  await expect(page.locator('#trader-convert-form')).not.toHaveClass(/hidden/);
  await expect(page.locator('#tv-weight')).toHaveValue('100.000');
  await expect(page.locator('#tv-price')).toHaveValue('110');
  await expect(page.locator('#tv-preview')).toContainText('11,000');
  // after: gold 0, cash we owe 500 + 11000
  await expect(page.locator('#tv-preview')).toContainText('11,500');
  page.on('dialog', d => d.accept());
  await page.click('#tv-btn');
  await expect.poll(() => calls.some(c => c.name === 'trader_gold_to_cash')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'trader_gold_to_cash').body)).toMatchObject({ p_trader: 't1', p_weight: 100, p_karat: 24, p_price: 110, p_direction: 'we_owe_gold' });

  await page.click('button:has-text("صرف كاش")');
  await expect(page.locator('#trader-cash-form')).not.toHaveClass(/hidden/);
  await expect(page.locator('#trader-convert-form')).toHaveClass(/hidden/);
  await page.fill('#tc-amount', '500');
  await page.click('#tc-btn');
  await expect.poll(() => calls.some(c => c.name === 'trader_cash_move')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'trader_cash_move').body)).toMatchObject({ p_trader: 't1', p_direction: 'out', p_amount: 500, p_daily: true });
  expect(errs).toEqual([]);
});

test('statement shows the new rows in the store currency', async ({ page }) => {
  const d = db();
  d.trader_movements.push(
    { id: 'm2', store_id: STORE, trader_id: 't1', movement_type: 'debt_decrease', source: 'gold_to_cash', karat: 24, weight_grams: 100, gold_24k_equivalent: 100, fab_fee_amount: 0, notes: 'تسكير عملات: 100 غ عيار 24 × 110 = 11000', created_at: T },
    { id: 'm3', store_id: STORE, trader_id: 't1', movement_type: 'debt_increase', source: 'gold_to_cash', gold_24k_equivalent: 0, fab_fee_amount: 11000, created_at: T },
    { id: 'm4', store_id: STORE, trader_id: 't1', movement_type: 'debt_decrease', source: 'cash_out', gold_24k_equivalent: 0, fab_fee_amount: 11500, created_at: T });
  await install(page, { db: d });
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  await expect(page.locator('#stCashRows')).toContainText('صرف كاش للتاجر');
  await expect(page.locator('#stCashRows')).toContainText('تسكير عملات');
  await expect(page.locator('#stCashRows')).toContainText('USD');
  await expect(page.locator('#stGoldNet')).toContainText('0.00');
  await expect(page.locator('#stCashCards')).toContainText('0.00');
  await expect(page.locator('button:has-text("PDF")')).toBeVisible();
});
