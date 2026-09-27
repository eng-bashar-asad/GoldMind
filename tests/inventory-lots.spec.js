const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('inventory shows scrap gold boxes by weight, with their lots', async ({ page }) => {
  const pieces = Array.from({ length: 3 }, (_, i) => ({ id: 'p' + i, store_id: STORE, status: 'available', karat: 18, weight_grams: 25.52, box_name: 'قطع ذهبية' }));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Bashar' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces,
    gold_stock_lots: [
      { id: 'l1', store_id: STORE, karat: 21, weight_grams_total: 12.4, weight_grams_remaining: 12.4, box_name: 'كسر 21', source_invoice_id: 'inv1', created_at: '2026-09-27T10:00:00Z' },
      { id: 'l2', store_id: STORE, karat: 21, weight_grams_total: 8, weight_grams_remaining: 5.5, box_name: 'كسر 21', source_invoice_id: null, notes: 'رصيد', created_at: '2026-09-20T10:00:00Z' },
      { id: 'l3', store_id: STORE, karat: 18, weight_grams_total: 3.2, weight_grams_remaining: 3.2, box_name: 'كسر 18', created_at: '2026-09-21T10:00:00Z' }],
    invoices: [{ id: 'inv1', store_id: STORE, invoice_number: 'PINV-2026-000001' }],
  } });
  await page.setViewportSize({ width: 393, height: 800 });
  await page.goto('/inventory-list-ar.html');
  await expect(page.locator('#lot-boxes')).toContainText('كسر 21');
  await expect(page.locator('#lot-boxes')).toContainText('17.90');
  await page.locator('[data-lot-box="كسر 21"]').click();
  await expect(page.locator('#lot-detail')).toContainText('PINV-2026-000001');
  await expect(page.locator('#lot-detail')).toContainText('من أصل 8.00');
});
