// أرصدة الفرع (inventory): per box × karat — pieces count / gross / accounting / pure 24k; scrap boxes by weight.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const db = (role, permissions) => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role, permissions, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  pieces: [
    { id: 'p1', store_id: STORE, barcode: '000001', karat: 18, weight_grams: 10, accounting_weight_grams: 8, box_name: 'قطع ذهبية', status: 'available' },
    { id: 'p2', store_id: STORE, barcode: '000002', karat: 21, weight_grams: 8, accounting_weight_grams: 8, box_name: 'قطع ذهبية', status: 'available' },
    { id: 'p3', store_id: STORE, barcode: '000003', karat: 18, weight_grams: 5, box_name: 'قطع ذهبية', status: 'sold' },
  ],
  gold_stock_lots: [{ id: 'l1', store_id: STORE, karat: 21, weight_grams_total: 24, weight_grams_remaining: 24, box_name: 'كسر 21' }],
});

test('owner sees the branch balances: per box and karat, pure 24k total', async ({ page }) => {
  await install(page, { db: db('owner', {}) });
  await page.goto('/inventory-list-ar.html');
  await page.locator('#bbBtn').click();
  const t = page.locator('#bbTable');
  await expect(t).toBeVisible();
  // 18k: 8 × 18/24 = 6 ; 21k piece: 8 × 21/24 = 7 ; scrap 21: 24 × 21/24 = 21 → 34
  await expect(t.locator('tr', { hasText: 'قطع ذهبية' }).locator('td').last()).toHaveText('13.000');
  await expect(t.locator('tr', { hasText: 'كسر 21' }).locator('td').last()).toHaveText('21.000');
  await expect(page.locator('#bbBody')).toContainText('34.000');
});

test('employee without the permission does not get the button', async ({ page }) => {
  await install(page, { db: db('employee', { view_inventory: true }) });
  await page.goto('/inventory-list-ar.html');
  await expect(page.locator('#piece-count')).not.toHaveText('…');
  await expect(page.locator('#bbBtn')).toHaveClass(/\bhidden\b/);
});
