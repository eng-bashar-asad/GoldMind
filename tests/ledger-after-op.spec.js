// بشار 2026-11-22: after an operation on a trader's / customer's account the page goes back to the
// top of the account, the form closes and a short «تمت العملية ✓» shows.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const base = extra => ({ stores: [{ id: STORE, name: 'x', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], ...extra });

test('trader account: re-shown after an operation → form closed, top, toast', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 700 });
  await install(page, { generic: true, db: base({ traders: [{ id: 't1', store_id: STORE, name: 'جليل' }], gold_prices: [], pieces: [], trader_movements: [] }) });
  await page.goto('/ledger-ar.html?trader=t1');
  await expect(page.locator('#trader-detail-view')).not.toHaveClass(/\bhidden\b/);
  await expect(page.getByText('تمت العملية')).toHaveCount(0); // just opening: no toast
  await page.evaluate(() => { document.getElementById('trader-convert-form').classList.remove('hidden'); document.body.style.minHeight = '4000px'; window.scrollTo(0, 1500); });
  await page.evaluate(async () => { const id = currentTraderId; await load(); showTraderDetail(id); }); // what every save does
  await expect(page.locator('#trader-convert-form')).toHaveClass(/\bhidden\b/);
  await expect(page.getByText('تمت العملية ✓')).toHaveCount(1);
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
});

test('customer account: same after an operation, and «pay» opens the form only once', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 700 });
  await install(page, { generic: true, db: base({ customers: [{ id: 'c1', store_id: STORE, name: 'نسرين' }], customer_debts: [] }) });
  await page.goto('/customer-debts-ar.html?open=c1&pay=1');
  await expect(page.locator('#settle-form')).not.toHaveClass(/\bhidden\b/);
  await expect(page).not.toHaveURL(/pay=1/);
  await page.evaluate(async () => { const id = currentCustomerId; await load(); showCustomerDetail(id); });
  await expect(page.locator('#settle-form')).toHaveClass(/\bhidden\b/);
  await expect(page.getByText('تمت العملية ✓')).toHaveCount(1);
});
