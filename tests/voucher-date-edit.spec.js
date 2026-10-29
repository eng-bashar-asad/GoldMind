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
  await page.locator('#autoRowModal button', { hasText: 'فتح الحركة' }).click();
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
  await page.locator('#autoRowModal button', { hasText: 'فتح الحركة' }).click();
  await page.waitForURL(/invoice-print-ar\.html\?id=inv1/);
});

test('customer page: change the date of a payment from the row', async ({ page }) => {
  const calls = await install(page, { generic: true, rpc: { set_voucher_date: () => ({ body: null }) }, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ديمة الانصاري' }], invoices: [],
    customer_debts: [{ id: 'p1', store_id: STORE, customer_id: 'c1', movement_type: 'debt_decrease', source: 'payment', cash_amount: 300, cash_movement_id: 'cm9', created_at: '2026-10-05T10:00:00Z' }],
  } });
  await page.goto('/customer-debts-ar.html?open=c1');
  await page.click('button:has-text("تعديل التاريخ")');
  await page.fill('#vd-in-p1', '2026-10-02');
  await page.click('#vd-p1 button:has-text("حفظ التاريخ")');
  await expect.poll(() => calls.some(c => c.name === 'set_voucher_date')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'set_voucher_date').body)).toEqual({ p_cash_movement: 'cm9', p_date: '2026-10-02' });
});

test('trader page: change the date of a cash receipt from the row', async ({ page }) => {
  const calls = await install(page, { generic: true, rpc: { set_voucher_date: () => ({ body: null }) }, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
    trader_movements: [{ id: 'tm1', store_id: STORE, trader_id: 't1', movement_type: 'debt_increase', source: 'cash_in', fab_fee_amount: 100, gold_24k_equivalent: 0, created_at: '2026-10-05T10:00:00Z' }],
    cash_movements: [{ id: 'cm7', store_id: STORE, trader_movement_id: 'tm1' }],
  } });
  await page.goto('/ledger-ar.html?trader=t1');
  await page.click('button:has-text("تعديل التاريخ")');
  await page.fill('#vd-in-tm1', '2026-10-03');
  await page.click('#vd-tm1 button:has-text("حفظ التاريخ")');
  await expect.poll(() => calls.some(c => c.name === 'set_voucher_date')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'set_voucher_date').body)).toEqual({ p_cash_movement: 'cm7', p_date: '2026-10-03' });
});
