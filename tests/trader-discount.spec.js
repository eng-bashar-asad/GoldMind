// Discount on a trader's cash balance: in his favour = less profit, in ours = more profit.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-09-15T10:00:00Z';

test('trader page: discount form sends the right side', async ({ page }) => {
  const calls = await install(page, { generic: true, rpc: { trader_discount: () => ({ body: 'x' }) }, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
    trader_movements: [{ id: 'm1', store_id: STORE, trader_id: 't1', movement_type: 'debt_decrease', source: 'cash_out', fab_fee_amount: 1000, gold_24k_equivalent: 0, created_at: T },
                       { id: 'm2', store_id: STORE, trader_id: 't1', movement_type: 'debt_increase', source: 'discount', fab_fee_amount: 50, gold_24k_equivalent: 0, created_at: T }]
  } });
  page.on('dialog', d => d.accept());
  await page.goto('/ledger-ar.html?trader=t1');
  await expect(page.locator('#trader-move-m2')).toContainText('خصم لصالح التاجر');
  await page.click('button:has-text("خصم على الحساب النقدي")');
  await expect(page.locator('#td-balance')).toContainText('التاجر مديون للمحل');
  await page.click('.td-for[data-for="shop"]');
  await page.fill('#td-amount', '25');
  await page.click('#td-btn');
  await expect.poll(() => calls.some(c => c.name === 'trader_discount')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'trader_discount').body)).toMatchObject({ p_trader: 't1', p_for: 'shop', p_amount: 25 });
});

test('profit report counts trader discounts', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', vat_rate: 0 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    gold_prices: [], pieces: [], diamond_pieces: [], invoices: [], invoice_items: [],
    trader_movements: [
      { id: 'a', store_id: STORE, source: 'discount', movement_type: 'debt_decrease', fab_fee_amount: 100, created_at: T },
      { id: 'b', store_id: STORE, source: 'discount', movement_type: 'debt_increase', fab_fee_amount: 30, created_at: T }]
  } });
  await page.goto('/profit-report-ar.html');
  await page.fill('#date-from', '2026-09-01');
  await page.fill('#date-to', '2026-09-30');
  await page.click('#apply-filters-btn');
  const br = page.locator('#pr-brief');
  await expect(br.locator('tr', { hasText: 'خصومات التجار لصالح المحل' })).toContainText('100.00');
  await expect(br.locator('tr', { hasText: 'خصومات لصالح التجار' })).toContainText('30.00');
  await expect(br.locator('tr', { hasText: 'صافي ربح المحل' })).toContainText('70.00');
});
