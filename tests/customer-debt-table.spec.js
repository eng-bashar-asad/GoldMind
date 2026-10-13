// Customer debt table: payments clear the oldest open debt first; a fully paid customer is left out.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const ago = d => new Date(Date.now() - d * 86400000).toISOString();

test('oldest debt is paid first; per-debt ages and gaps; paid customers are left out', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ديمة الانصاري' }, { id: 'c2', store_id: STORE, name: 'بيت دولة' }, { id: 'c3', store_id: STORE, name: 'سامي' }],
    customer_debts: [
      { id: 'a', store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', source: null, cash_amount: 500, created_at: ago(40) },
      { id: 'b', store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', source: null, cash_amount: 200, created_at: ago(25) },
      { id: 'p', store_id: STORE, customer_id: 'c1', movement_type: 'debt_decrease', source: 'payment', cash_amount: 300, created_at: ago(10) },
      { id: 'd', store_id: STORE, customer_id: 'c2', movement_type: 'debt_increase', source: null, cash_amount: 100, created_at: ago(30) },
      { id: 'e', store_id: STORE, customer_id: 'c2', movement_type: 'debt_decrease', source: 'payment', cash_amount: 100, created_at: ago(5) },
      { id: 'f', store_id: STORE, customer_id: 'c3', movement_type: 'debt_increase', source: null, cash_amount: 100, created_at: ago(20) },
      { id: 'g', store_id: STORE, customer_id: 'c3', movement_type: 'debt_decrease', source: 'payment', cash_amount: 150, created_at: ago(3) },
      { id: 'h', store_id: STORE, customer_id: 'c3', movement_type: 'debt_increase', source: null, cash_amount: 80, created_at: ago(1) },
    ],
  } });
  await page.goto('/customer-debt-table-ar.html');
  await expect(page.locator('#page-content')).not.toHaveClass(/\bhidden\b/);
  const text = await page.locator('#customers').innerText();
  expect(text).toContain('ديمة الانصاري');
  expect(text).toContain('400.00');            // 200 + 200 still open
  expect(text).not.toContain('بيت دولة');     // paid in full
  expect(text).toContain('15 يوم');           // second debt came 15 days after the first
  expect(text).toContain('30.00');            // sami: 80 new debt minus 50 credit left from his payment
  await expect(page.locator('#grandCount')).toHaveText('2 من 2 زبون في الكشف');
});

test('only the customers ticked for the report are counted and sent', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED', country: 'AE' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ديمة الانصاري' }, { id: 'c3', store_id: STORE, name: 'سامي' }],
    customer_debts: [
      { id: 'a', store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', source: null, cash_amount: 500, created_at: ago(40) },
      { id: 'f', store_id: STORE, customer_id: 'c3', movement_type: 'debt_increase', source: null, cash_amount: 100, created_at: ago(20) },
    ],
  } });
  await page.goto('/customer-debt-table-ar.html');
  await expect(page.locator('#grandTotal')).toHaveText(/600\.00/);
  // leave out ديمة
  await page.locator('section.cust', { hasText: 'ديمة' }).locator('input[type=checkbox]').uncheck();
  await expect(page.locator('#grandTotal')).toHaveText(/100\.00/);
  await expect(page.locator('#grandCount')).toHaveText('1 من 2 زبون في الكشف');
  // the report node used for PDF/WhatsApp has no excluded customer
  const names = await page.evaluate(() => [...debtReportNode().querySelectorAll('section.cust')].map(s => s.innerText));
  expect(names.length).toBe(1);
  expect(names[0]).toContain('سامي');
  expect(names[0]).not.toContain('ديمة');
  // select all again
  await page.evaluate(() => setAllPicks(true));
  await expect(page.locator('#grandCount')).toHaveText('2 من 2 زبون في الكشف');
});
