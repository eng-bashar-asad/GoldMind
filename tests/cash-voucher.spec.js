// سند قبض / صرف: customer, trader or expense, in any currency (account in store currency, cash box in the paid currency).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  stores: [{ id: STORE, name: 'x', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'حسن درويش', phone: '0944' }, { id: 'c2', store_id: STORE, name: 'ديمة' }],
  traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
  expense_categories: [{ id: 'e1', store_id: STORE, name: 'كهرباء' }],
  customer_debts: [{ id: 'd1', store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', cash_amount: 500 }],
  trader_movements: []
});

test('customer receipt in SYP with a rate', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const calls = await install(page, { generic: true, db: db(), rpc: { cash_voucher: () => ({ body: { ok: true } }) } });
  page.on('dialog', d => d.accept());
  await page.goto('/cash-voucher-ar.html');
  await page.fill('#cv-who-search', 'حسن');
  await expect(page.locator('#cv-who')).toHaveValue('c1');
  await expect(page.locator('#cv-bal')).toContainText('عليه: 500.00 USD');
  await page.selectOption('#cv-cur', 'SYP');
  await page.fill('#cv-rate', '13000');
  await page.fill('#cv-amount', '1300000');
  await expect(page.locator('#cv-preview')).toContainText('1,300,000.00 SYP');
  await expect(page.locator('#cv-preview')).toContainText('100.00 USD');
  await page.click('#cv-btn');
  await expect(page.locator('#cv-ok')).toBeVisible();
  const p = JSON.parse(calls.find(c => c.name === 'cash_voucher').body).p;
  expect(p).toMatchObject({ kind: 'in', party: 'customer', party_id: 'c1', amount: 1300000, currency: 'SYP', fx_rate: 13000, method: 'cash' });
  expect(errs).toEqual([]);
});

test('expense payment, and trader voucher opened from the trader page', async ({ page }) => {
  const calls = await install(page, { generic: true, db: db(), rpc: { cash_voucher: () => ({ body: { ok: true } }) } });
  page.on('dialog', d => d.accept());
  await page.goto('/cash-voucher-ar.html');
  await page.click('.seg.kind [data-kind="out"]');
  await page.click('.seg.party [data-party="expense"]');
  await expect(page.locator('#cv-who')).toHaveValue('e1');
  await page.fill('#cv-amount', '50');
  await page.click('#cv-btn');
  await expect(page.locator('#cv-ok')).toBeVisible();
  expect(JSON.parse(calls.find(c => c.name === 'cash_voucher').body).p).toMatchObject({ kind: 'out', party: 'expense', category_id: 'e1', amount: 50, currency: 'USD', fx_rate: null });

  await page.goto('/cash-voucher-ar.html?party=trader&kind=out&id=t1');
  await expect(page.locator('#cv-who')).toHaveValue('t1');
  await expect(page.locator('.seg.kind [data-kind="out"]')).toHaveClass(/on/);
  // receipts can't be for an expense
  await page.click('.seg.kind [data-kind="in"]');
  await expect(page.locator('.seg.party [data-party="expense"]')).toBeDisabled();
});
