// Searching the gold stock for a barcode that is a diamond piece says it is in the diamond warehouse.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('barcode of a diamond piece points to the diamond warehouse', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD', diamonds_enabled: true }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Bashar' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000004', status: 'available', karat: 18, weight_grams: 5, box_name: 'قطع ذهبية' }],
    diamond_pieces: [{ id: 'd1', store_id: STORE, barcode: 'D000004', status: 'available' }],
    gold_stock_lots: [],
  } });
  await page.goto('/inventory-list-ar.html');
  await page.evaluate(() => { document.getElementById('search-panel').classList.remove('hidden'); });
  await page.fill('#search-barcode', 'D000004');
  await page.press('#search-barcode', 'Enter');
  await expect(page.locator('#search-results-list')).toContainText('في مستودع الألماس');
  await expect(page.locator('#search-results-list a[href="diamond-inventory-list-ar.html"]')).toBeVisible();
});

test('stock page shows a card that leads to the diamond warehouse', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD', diamonds_enabled: true }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Bashar' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000004', status: 'available', karat: 18, weight_grams: 5, box_name: 'قطع ذهبية' }],
    diamond_pieces: [{ id: 'd1', store_id: STORE, barcode: 'D000001', status: 'available', diamond_carat: 1.72 }],
    gold_stock_lots: [],
  } });
  await page.goto('/inventory-list-ar.html');
  const card = page.locator('#diamond-card');
  await expect(card).toContainText('مستودع الألماس');
  await expect(card).toContainText('1 قطعة');
  await expect(card).toContainText('1.72 ct');
  await expect(page.locator('#piece-count')).toHaveText('1 قطعة');   // gold count unchanged
  await card.locator('button').click();
  await expect(page).toHaveURL(/diamond-inventory-list-ar\.html/);
});

test('search filter: sold to customers vs sold to traders', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Bashar' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [
      { id: 'p1', store_id: STORE, barcode: '000001', status: 'available', karat: 18, weight_grams: 5, box_name: 'قطع ذهبية' },
      { id: 'p2', store_id: STORE, barcode: '000002', status: 'sold', karat: 18, weight_grams: 6, box_name: 'قطع ذهبية' },
      { id: 'p3', store_id: STORE, barcode: '000003', status: 'given_to_trader', karat: 18, weight_grams: 7, box_name: 'قطع ذهبية' }],
    diamond_pieces: [], gold_stock_lots: [],
  } });
  await page.goto('/inventory-list-ar.html');
  await page.evaluate(() => { document.getElementById('search-panel').classList.remove('hidden'); });
  const list = page.locator('#search-results-list');
  await page.selectOption('#search-status', 'given_to_trader');
  await page.evaluate(() => runSearch());
  await expect(list).toContainText('000003');
  await expect(list).not.toContainText('000002');
  await expect(list).toContainText('مباعة لتاجر');
  await page.selectOption('#search-status', 'sold');
  await page.evaluate(() => runSearch());
  await expect(list).toContainText('000002');
  await expect(list).not.toContainText('000003');
});
