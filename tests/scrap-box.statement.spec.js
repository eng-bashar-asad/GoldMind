// Scrap box statement (بشار 2026-11-16): every in/out of «كسر 21», newest first with the balance after
// each row; a trader voucher opens an edit sheet that saves through edit_scrap_movement.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const base = { stores: [{ id: STORE, name: 'محل', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], gold_stock_lots: [{ id: 'l1', store_id: STORE, box_name: 'كسر 21', karat: 21, weight_grams_remaining: 20 }] };
const ROWS = [
  { kind: 'invoice', ref_id: 'i1', at: '2026-11-01T10:00:00Z', grams: 50, title: 'شراء كسر', sub: 'PINV-1', editable: false },
  { kind: 'trader', ref_id: 'm1', at: '2026-11-05T10:00:00Z', grams: -30, title: 'إخراج كسر للتاجر عمار', sub: 'TOUT-1', trader_id: 't1', source: 'scrap_given', karat: 21, editable: true },
];

test('statement: newest first, running balance, edit a trader voucher', async ({ page }) => {
  const calls = await install(page, { db: base, rpc: { scrap_box_statement: () => ({ body: ROWS }), edit_scrap_movement: () => ({ body: null }) } });
  await page.goto('/scrap-box-ar.html?box=' + encodeURIComponent('كسر 21'));
  const rows = page.locator('#sb-list .sb-row');
  await expect(rows).toHaveCount(2);
  await expect(rows.nth(0)).toContainText('إخراج كسر للتاجر عمار');
  await expect(rows.nth(0)).toContainText('الرصيد 20.00');
  await expect(rows.nth(1)).toContainText('الرصيد 50.00');
  await expect(page.locator('#sb-tiles')).toContainText('20.00');
  await rows.nth(0).click();
  await expect(page.locator('#sb-w')).toHaveValue('30');
  await page.fill('#sb-w', '25');
  await page.locator('#sb-save').click();
  await expect.poll(() => calls.find(c => c.name === 'edit_scrap_movement')).toBeTruthy();
  const body = JSON.parse(calls.find(c => c.name === 'edit_scrap_movement').body);
  expect(body).toEqual({ p_movement: 'm1', p_weight: 25, p_notes: null });
  // an invoice row opens the invoice instead
  await rows.nth(1).click();
  await expect(page.locator('#sb-sh-body a')).toHaveAttribute('href', /invoice-print-ar\.html\?id=i1/);
});
