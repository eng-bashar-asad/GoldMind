// Expenses in another currency: amount + currency + rate go to record_expense; the list shows the paid currency.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('expense paid in SYP', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  let sent = null;
  await install(page, { generic: true, rpc: { record_expense: a => { sent = a.p; return { body: 'e1' }; } }, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD', secondary_currency: 'SYP', secondary_currency_rate: 13000 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    expense_categories: [{ id: 'k1', store_id: STORE, name: 'كهرباء' }],
    gold_prices: [], inventory_gifts: [],
    expense_entries: [{ id: 'x1', store_id: STORE, category_id: 'k1', amount: 50, fx_amount: 650000, fx_currency: 'SYP', description: 'فاتورة', created_at: new Date().toISOString(), category: { name: 'كهرباء' } }]
  } });
  await page.goto('/expense-entry-ar.html');
  await expect(page.locator('#list')).toContainText('650,000 SYP');
  await expect(page.locator('#list')).toContainText('50.00 USD');
  await page.click('button:has-text("كهرباء")');
  await page.fill('#amount-input', '1300000');
  await page.selectOption('#cur-input', 'SYP');
  await expect(page.locator('#rate-input')).toHaveValue('13000');
  await expect(page.locator('#fx-note')).toContainText('100.00 USD');
  await page.click('#save-btn');
  await expect.poll(() => sent).not.toBeNull();
  expect(sent).toMatchObject({ category_id: 'k1', amount: 1300000, currency: 'SYP', fx_rate: 13000 });
  expect(errs).toEqual([]);
});
