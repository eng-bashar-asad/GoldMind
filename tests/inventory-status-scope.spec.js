// المخزن: status tiles follow the open box; "الكل" includes sold and reserved.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('inventory: status filter is scoped to the open box', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const pc = (id, bc, box, status) => ({ id, store_id: STORE, barcode: bc, weight_grams: 2, karat: 18, status, box_name: box, created_at: '2026-10-01T00:00:00Z' });
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [pc('a', '000001', 'ميروبا', 'available'), pc('b', '000002', 'ميروبا', 'sold'), pc('c', '000003', 'ميروبا', 'reserved'),
             pc('d', '000004', 'قطع ذهبية', 'sold'), pc('e', '000005', 'قطع ذهبية', 'available')],
    gold_stock_lots: []
  } });
  await page.goto('/inventory-list-ar.html');
  await expect(page.locator('#gmStatusTiles [data-st="sold"] b')).toHaveText('2');
  await page.evaluate(() => enterBox('ميروبا'));
  await expect(page.locator('#gmStatusTiles [data-st="sold"] b')).toHaveText('1');
  await expect(page.locator('#gmStatusTiles [data-st="all"] b')).toHaveText('3');
  await page.click('#gmStatusTiles [data-st="sold"]');
  await expect(page.locator('#piece-count')).toHaveText('1 قطعة');
  await page.click('#gmStatusTiles [data-st="all"]');
  await expect(page.locator('#piece-count')).toHaveText('3 قطعة');
  await page.click('#gmStatusTiles [data-st="available"]');
  await expect(page.locator('#piece-count')).toHaveText('1 قطعة');
  expect(errs).toEqual([]);
});
