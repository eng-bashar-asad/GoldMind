// إنتاج القطع: lots grouped in karat scrap boxes (كسر 18/21/22/24 always shown).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('production: scrap lots grouped by karat box', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const lot = (id, box, k, w) => ({ id, store_id: STORE, box_name: box, karat: k, weight_grams_total: w, weight_grams_remaining: w, cost_fabrication_per_gram: 0, created_at: '2026-10-01T00:00:00Z' });
  const calls = await install(page, { generic: true, rpc: {
      next_piece_barcode: () => ({ body: '000900' }),
      consume_gold_stock_lot: () => ({ body: null }) }, db: {
    stores: [{ id: STORE, currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    gold_stock_lots: [lot('l1', 'كسر 18', 18, 18.25), { ...lot('l2', 'كسر 18', 18, 31.96), created_at: '2026-10-02T00:00:00Z' }, lot('l3', 'ذهب مشغول', 21, 10)]
  } });
  await page.goto('/stock-production-ar.html');
  const list = page.locator('#lots-list');
  await expect(list).toContainText('كسر 18');
  await expect(list).toContainText('50.21 غ');
  await expect(list).toContainText('كسر 24');
  await expect(list).toContainText('ذهب مشغول');
  await expect(list).not.toContainText('متبقي');
  await page.getByText('كسر 18', { exact: true }).click();
  // the scrap box is one pool: total only, no per-purchase split
  await expect(list).toContainText('إنتاج قطع من كسر 18 — المتوفر 50.21غ');
  await expect(list.getByText('متبقي')).toHaveCount(0);
  await page.getByText('إنتاج قطع من كسر 18').click();
  await expect(page.locator('#produce-btn-pool-18')).toBeVisible();
  // 20 g taken from the pool: the oldest purchase first
  await page.getByText('+ إضافة قطعة').click();
  await page.fill('#rows-pool-18 input[placeholder="الوزن"]', '20');
  await page.click('#produce-btn-pool-18');
  await expect.poll(() => calls.filter(c => c.name === 'consume_gold_stock_lot').length).toBe(2);
  const takes = calls.filter(c => c.name === 'consume_gold_stock_lot').map(c => JSON.parse(c.body));
  expect(takes).toEqual([{ target_lot_id: 'l1', amount: 18.25 }, { target_lot_id: 'l2', amount: 1.75 }]);
  expect(errs).toEqual([]);
});
