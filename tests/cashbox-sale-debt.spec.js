// A sale left partly on debt (بشار 2026-11-16): the daily box shows the whole invoice in one row,
// linked to one «باقي على» row with the debt — no "بالدين" +/− pair. The balance is unchanged.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const at = m => { const d = new Date(); d.setHours(0, 0, 0, 0); return new Date(d.getTime() + m * 60000).toISOString(); };

test('sale on partial debt: full invoice row + one «باقي على» row', async ({ page }) => {
  const t = at(60);
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    daily_cash_log: [
      { id: 'p', store_id: STORE, direction: 'in', amount: 5000, currency: 'USD', operation_type: 'مبيعات لـ سعيد', notes: 'تحصيل جزئي INV-9 (5000.00 نقداً)', cash_movement_id: 'c1', cm: { invoice_id: 'i9', inv: { total_amount: 10000 } }, created_at: t },
      { id: 'd', store_id: STORE, direction: 'in', amount: 5000, currency: 'USD', operation_type: 'مبيعات لـ سعيد', notes: 'INV-9 — بالدين', link_group: 'debt_i9', created_at: t },
      { id: 'o', store_id: STORE, direction: 'out', amount: 5000, currency: 'USD', operation_type: 'دين على سعيد', notes: 'INV-9', link_group: 'debt_i9', created_at: t },
    ] } });
  await page.goto('/daily-cashbox-ar.html');
  const rows = page.locator('#cashbox-table-body > tr');
  await expect(rows).toHaveCount(2);
  await expect(page.locator('#cashbox-table-body')).not.toContainText('بالدين');
  await expect(page.locator('#cashbox-table-body')).toContainText('10,000.00');
  await expect(page.locator('#cashbox-table-body')).toContainText('باقي على سعيد');
  await expect(page.locator('#dcFoot')).toContainText('5,000.00');
});
