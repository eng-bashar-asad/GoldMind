// Gold received from a trader in a settlement goes into the chosen scrap box,
// keeping the same pure gold as the trader's statement.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('incoming settlement: 279.22 g of 24K goes into «كسر 18» as 372.293 g, linked to the settlement', async ({ page }) => {
  const calls = await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
    trader_movements: []
  } });
  await page.route(/rest\/v1\/trader_movements/, route => route.request().method() === 'POST'
    ? route.fulfill({ status: 201, json: { id: 'mv1', created_at: '2026-10-08T13:37:44Z' } }) : route.fallback());
  page.on('dialog', d => d.accept());
  await page.goto('/ledger-ar.html?trader=t1');
  await page.click('button[onclick="toggleSettleForm()"]');
  await expect(page.locator('#settle-box-wrap')).toHaveClass(/hidden/);  // outgoing: no stock box
  await page.click('#settle-dir-in');
  await page.fill('#settle-weight', '279.22');
  await page.selectOption('#settle-karat', '24');
  await expect(page.locator('#settle-box')).toHaveValue('24');       // defaults to the same karat
  await page.selectOption('#settle-box', '18');
  await expect(page.locator('#settle-box-preview')).toContainText('372.29');
  await page.fill('#settle-notes', 'عيار 745');
  await page.click('#settle-btn');
  await expect.poll(() => calls.some(c => c.name === 'gold_stock_lots' && c.method === 'POST')).toBe(true);
  const lot = JSON.parse(calls.find(c => c.name === 'gold_stock_lots' && c.method === 'POST').body);
  expect(lot).toMatchObject({ box_name: 'كسر 18', karat: 18, weight_grams_total: 372.293, weight_grams_remaining: 372.293, trader_id: 't1', trader_movement_id: 'mv1', created_at: '2026-10-08T13:37:44Z' });
  expect(lot.notes).toContain('279.22 غ عيار 24');
  expect(lot.notes).toContain('عيار 745');
});

test('incoming settlement with "لا يُدخل للمخزون": no stock lot', async ({ page }) => {
  const calls = await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }], trader_movements: []
  } });
  let saved = 0;
  await page.route(/rest\/v1\/trader_movements/, route => route.request().method() === 'POST'
    ? (saved++, route.fulfill({ status: 201, json: { id: 'mv1', created_at: '2026-10-08T13:37:44Z' } })) : route.fallback());
  await page.goto('/ledger-ar.html?trader=t1');
  await page.click('button[onclick="toggleSettleForm()"]');
  await page.click('#settle-dir-in');
  await page.fill('#settle-weight', '10');
  await page.selectOption('#settle-box', '');
  await page.click('#settle-btn');
  await expect.poll(() => saved).toBe(1);
  await page.waitForTimeout(400);
  expect(calls.some(c => c.name === 'gold_stock_lots' && c.method === 'POST')).toBe(false);
});
