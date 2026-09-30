// Goods out to a trader by weight: several lines with different making in one voucher.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('give stock by weight: several lines, one voucher', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const calls = await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'تاجر أ' }],
    trader_movements: [],
  } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/ledger-ar.html?trader=t1&action=give');
  await page.waitForFunction(() => typeof setGiveStockMode === 'function' && typeof currentTraderId !== 'undefined' && currentTraderId === 't1');
  await page.evaluate(() => { if (document.getElementById('give-stock-form').classList.contains('hidden')) toggleGiveStockForm(); setGiveStockMode('bulk'); });
  const line = async (w, k, fab, cost) => {
    await page.fill('#gsb-weight', String(w)); await page.selectOption('#gsb-karat', String(k));
    await page.fill('#gsb-fab', String(fab)); if (cost != null) await page.fill('#gsb-cost', String(cost));
  };
  await line(100, 18, 10, 6);
  await page.click('button:has-text("إضافة السطر للسند")');
  await line(50, 21, 25);
  await page.click('button:has-text("إضافة السطر للسند")');
  await line(10, 18, 30);                       // left in the fields: saved too
  await expect(page.locator('#gsb-lines > div')).toHaveCount(2);
  await expect(page.locator('#gsb-preview-fee-label')).toContainText('3 سطر');
  await page.click('#gsb-btn');
  await expect.poll(() => calls.some(c => c.method === 'POST' && c.name === 'trader_movements')).toBe(true);
  const rows = JSON.parse(calls.find(c => c.method === 'POST' && c.name === 'trader_movements').body);
  expect(rows).toHaveLength(3);
  expect(rows.map(r => [r.weight_grams, r.karat, r.fab_fee_per_gram, r.cost_fab_per_gram])).toEqual([[100, 18, 10, 6], [50, 21, 25, null], [10, 18, 30, null]]);
  expect(new Set(rows.map(r => r.batch_id)).size).toBe(1);
  expect(rows[0].batch_id).toBeTruthy();
  expect(rows.every(r => r.source === 'stock_given' && r.movement_type === 'debt_decrease')).toBe(true);
  expect(errs).toEqual([]);
});
