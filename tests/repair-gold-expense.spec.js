// Repair gold: scrap-box gold for a repair is recorded as a cost expense (no cashbox effect).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const base = extra => ({
  stores: [{ id: STORE, name: 'محل الاختبار', currency: 'USD', address: 'دمشق', phone: '+963 11 000' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  ...extra
});

test('repair gold: grams from the scrap box are recorded as one cost expense, not a cashbox outflow', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  page.on('dialog', d => d.accept());
  const calls = await install(page, {
    db: base({
      expense_categories: [{ id: 'c1', store_id: STORE, name: 'كهرباء' }],
      gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 100 }],
      expense_entries: []
    }),
    rpc: { record_repair_gold: () => ({ body: 'e1' }) }
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/expense-entry-ar.html');

  await page.click('.cat-chip:has-text("تصاليح ذهب")');
  await expect(page.locator('#repair-form')).not.toHaveClass(/hidden/);
  await expect(page.locator('#money-form')).toHaveClass(/hidden/);
  await expect(page.locator('.cat-chip:has-text("كهرباء")')).toHaveCount(1);

  await page.selectOption('#repair-karat', '18');
  await page.fill('#repair-grams', '0.27');
  await expect(page.locator('#repair-preview')).toContainText('27.00');
  await page.fill('#repair-desc', 'تصليح سلسلة');
  await page.click('#repair-btn');

  await expect(page.locator('#save-success')).toContainText('سُجّل تصليح الذهب');
  const rec = JSON.parse(calls.find(c => c.name === 'record_repair_gold').body).p;
  expect(rec).toMatchObject({ store_id: STORE, karat: 18, grams: 0.27, description: 'تصليح سلسلة' });
  expect(calls.some(c => c.name === 'record_expense')).toBe(false);
  expect(errs).toEqual([]);
});

test('repair gold with a cash labour fee: two expenses, the cash one in the same category', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  page.on('dialog', d => d.accept());
  const calls = await install(page, {
    db: base({
      expense_categories: [{ id: 'cr', store_id: STORE, name: 'تصاليح ذهب' }],
      gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 100 }],
      expense_entries: []
    }),
    rpc: { record_repair_gold: () => ({ body: 'e1' }), record_expense: () => ({ body: 'e2' }) }
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/expense-entry-ar.html');
  await page.click('.cat-chip:has-text("تصاليح ذهب")');
  await page.selectOption('#repair-karat', '18');
  await page.fill('#repair-grams', '0.27');
  await page.fill('#repair-cash', '15');
  await page.click('#repair-btn');
  await expect(page.locator('#save-success')).toContainText('ذهب من الكسر + أجرة نقدية');
  const gold = JSON.parse(calls.find(c => c.name === 'record_repair_gold').body).p;
  const cash = JSON.parse(calls.find(c => c.name === 'record_expense').body).p;
  expect(gold.grams).toBe(0.27);
  expect(cash).toMatchObject({ store_id: STORE, category_id: 'cr', amount: 15, from_daily_cashbox: true });
  expect(errs).toEqual([]);
});

test('repair paid only in cash: no grams, nothing taken from the scrap box, one cash expense', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const calls = await install(page, {
    db: base({ expense_categories: [{ id: 'cr', store_id: STORE, name: 'تصاليح ذهب' }], gold_prices: [], expense_entries: [] }),
    rpc: { record_repair_gold: () => ({ body: 'e1' }), record_expense: () => ({ body: 'e2' }) }
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/expense-entry-ar.html');
  await page.click('.cat-chip:has-text("تصاليح ذهب")');
  await page.fill('#repair-desc', 'اجرة ورشة اوبي تصليح البازل');
  await page.fill('#repair-cash', '135');
  await page.click('#repair-btn');
  await expect(page.locator('#save-success')).toContainText('سُجّلت أجرة التصليح نقداً بدون ذهب');
  expect(calls.some(c => c.name === 'record_repair_gold')).toBe(false);
  const cash = JSON.parse(calls.find(c => c.name === 'record_expense').body).p;
  expect(cash).toMatchObject({ category_id: 'cr', amount: 135, from_daily_cashbox: true, description: 'أجرة تصليح ذهب — اجرة ورشة اوبي تصليح البازل' });
});
