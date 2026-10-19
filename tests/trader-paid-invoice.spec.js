// A trader whose only record is a purchase invoice paid in full (no balance movement):
// the invoice shows under his movements, and delete names it.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('paid invoice shows in an otherwise empty trader history; delete names it', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'حمدي' }],
    trader_movements: [],
    invoices: [{ id: 'i1', store_id: STORE, trader_id: 't1', invoice_number: 'PINV-2026-000007', type: 'buyTrader', status: 'paid', total_amount: 5180, created_at: '2026-10-03T18:10:00Z' }],
  } });
  await page.goto('/ledger-ar.html?trader=t1');
  const box = page.locator('#trader-other-invoices');
  await expect(box).toContainText('PINV-2026-000007');
  await expect(box).toContainText('5');
  await expect(page.locator('#empty-movements')).toHaveClass(/hidden/);
  page.on('dialog', d => d.dismiss());
  await page.evaluate(() => deleteTrader());
  await expect(page.locator('#gmToasts')).toContainText('PINV-2026-000007'); // shown as a notification
  expect(errs).toEqual([]);
});
