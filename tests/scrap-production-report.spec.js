const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');
const STORE = '11111111-1111-1111-1111-111111111111', STAFF = '33333333-3333-3333-3333-333333333333', USER = '22222222-2222-2222-2222-222222222222';
const piece = (id, barcode, w, acc, status) => ({ barcode, description_ar: 'خاتم', karat: 18, weight_grams: w, accounting_weight_grams: acc, status });

test('scrap production report: count, weights and karat per scrap box for the period', async ({ page }) => {
  const now = new Date().toISOString();
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    gold_stock_lots: [{ store_id: STORE, box_name: 'كسر 18' }, { store_id: STORE, box_name: 'كسر 21' }, { store_id: STORE, box_name: 'خواتم' }],
    piece_lot_draws: [
      { store_id: STORE, piece_id: 'p1', grams: 10, created_at: now, lot: { store_id: STORE, box_name: 'كسر 18', karat: 18 }, piece: piece('p1', '000201', 10, 9.5, 'available') },
      { store_id: STORE, piece_id: 'p1', grams: 0.5, created_at: now, lot: { store_id: STORE, box_name: 'كسر 18', karat: 18 }, piece: piece('p1', '000201', 10, 9.5, 'available') },
      { store_id: STORE, piece_id: 'p2', grams: 5, created_at: now, lot: { store_id: STORE, box_name: 'كسر 18', karat: 18 }, piece: piece('p2', '000202', 5, 5, 'sold') },
      { store_id: STORE, piece_id: 'p3', grams: 7, created_at: now, lot: { store_id: STORE, box_name: 'خواتم', karat: 18 }, piece: piece('p3', '000203', 7, 7, 'available') }
    ]
  } });
  await page.goto('/scrap-production-report-ar.html');
  await expect(page.locator('#rp-summary tr')).toHaveCount(1);
  await expect(page.locator('#rp-summary')).toContainText('كسر 18');
  await expect(page.locator('#rp-summary td').nth(2)).toHaveText('2');         // two pieces (p1 drew from two lots: counted once)
  await expect(page.locator('#rp-summary td').nth(3)).toHaveText('15.00');     // gross 10 + 5
  await expect(page.locator('#rp-summary td').nth(4)).toHaveText('14.50');     // accounting 9.5 + 5
  await expect(page.locator('#rp-summary td').nth(5)).toHaveText('15.50');     // drawn 10 + 0.5 + 5
  await expect(page.locator('#rp-tiles')).toContainText('15.00 غ');
  await expect(page.locator('#rp-list tr')).toHaveCount(2);                     // the non-scrap box piece is left out
  await expect(page.locator('#rp-list')).toContainText('مباعة');
  const q = calls.find(c => c.name === 'piece_lot_draws').url;
  expect(q).toContain('created_at=gte.'); expect(q).toContain('created_at=lt.');
});
