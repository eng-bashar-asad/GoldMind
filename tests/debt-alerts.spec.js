// Home page: open debts older than the days set in company settings show an alert box.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const ago = d => new Date(Date.now() - d * 86400000).toISOString();

test('overdue customer and trader debts are listed; a cleared debt is not', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED', debt_alert_days: 15, debt_alert_customers: true, debt_alert_traders: true }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ديمة الانصاري' }, { id: 'c2', store_id: STORE, name: 'بيت دولة' }],
    customer_debts: [
      { id: 'a', store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', source: null, cash_amount: 500, gold_grams_24k: 0, created_at: ago(30) },
      { id: 'b', store_id: STORE, customer_id: 'c2', movement_type: 'debt_increase', source: null, cash_amount: 100, gold_grams_24k: 0, created_at: ago(30) },
      { id: 'c', store_id: STORE, customer_id: 'c2', movement_type: 'debt_decrease', source: 'payment', cash_amount: 100, gold_grams_24k: 0, created_at: ago(5) },
    ],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
    trader_movements: [{ id: 'tm', store_id: STORE, trader_id: 't1', movement_type: 'debt_decrease', source: 'stock_given', fab_fee_amount: 200, gold_24k_equivalent: 0, created_at: ago(20) }],
  } });
  await page.goto('/index-ar.html');
  const box = page.locator('#debtAlertBox');
  await expect(box).not.toHaveClass(/\bhidden\b/);
  const text = await page.locator('#debtAlertBox').innerText();
  expect(text).toContain('ديمة الانصاري');
  expect(text).toContain('جليل');
  expect(text).not.toContain('بيت دولة');
  await expect(page.locator('#debtAlertBox a', { hasText: 'ديمة' })).toHaveAttribute('href', 'customer-debts-ar.html?open=c1');
  await expect(page.locator('#debtAlertBox a', { hasText: 'جليل' })).toHaveAttribute('href', 'ledger-ar.html?trader=t1');
  // each group collapses from its header; the header stays visible
  const cust = page.locator('#debtAlertBox details', { hasText: 'ديون الزبائن المتأخرة' });
  await expect(cust).toHaveAttribute('open', '');
  await cust.locator('summary').click();
  await expect(cust).not.toHaveAttribute('open', '');
  await expect(cust.locator('summary')).toContainText('ديون الزبائن المتأخرة');
  await expect(cust.locator('a')).toBeHidden();
  await cust.locator('summary').click();
  await expect(cust).toHaveAttribute('open', '');
});
