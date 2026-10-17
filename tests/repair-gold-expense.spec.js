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
