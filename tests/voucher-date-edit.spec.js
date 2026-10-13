// A cash voucher (سند قبض/صرف) can be moved to an earlier day from the cash box.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('voucher date can be changed; invoice rows are not offered', async ({ page }) => {
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    daily_cash_log: [
      { id: 'd1', store_id: STORE, direction: 'in', amount: 500, currency: 'AED', operation_type: 'دفعة من عميل', cash_movement_id: 'cm1', created_at: '2026-10-10T08:00:00Z' },
      { id: 'd2', store_id: STORE, direction: 'in', amount: 90, currency: 'AED', operation_type: 'بيع', cash_movement_id: 'cm2', cm: { invoice_id: 'inv1' }, created_at: '2026-10-10T09:00:00Z' },
    ],
  }, rpc: { set_voucher_date: () => ({ body: null }) } });
  page.on('dialog', d => d.accept());
  await page.goto('/daily-cashbox-ar.html');
  await page.waitForFunction(() => typeof allEntries !== 'undefined' && allEntries.length === 2);

  await page.evaluate(() => openEditModal('d1'));
  await expect(page.locator('#voucherDateModal')).toHaveClass(/\bflex\b/);
  await expect(page.locator('#voucherDateInput')).toHaveValue('2026-10-10');
  await page.fill('#voucherDateInput', '2026-10-01');
  await page.click('#voucherDateModal button:has-text("حفظ التاريخ")');
  await expect.poll(() => calls.some(c => c.name === 'set_voucher_date')).toBe(true);
  const body = JSON.parse(calls.find(c => c.name === 'set_voucher_date').body);
  expect(body).toEqual({ p_cash_movement: 'cm1', p_date: '2026-10-01' });
  await expect(page.locator('#voucherDateModal')).toHaveClass(/\bhidden\b/);

  // a row written from an invoice still opens the invoice, not the date box
  await page.evaluate(() => openEditModal('d2'));
  await page.waitForURL(/invoice-print-ar\.html\?id=inv1/);
});
