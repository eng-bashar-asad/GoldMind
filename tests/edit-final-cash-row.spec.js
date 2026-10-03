// An edited invoice shows once in the daily cashbox with its final value; editing
// a purchase without changing its amount posts no new money; buying from an
// individual hides the "photo of trader invoice" button.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const base = extra => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  ...extra
});

test('daily cashbox: first posting, reversal and new posting of one invoice show as one row', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const day = new Date(); day.setHours(0, 0, 0, 0);
  const T = h => new Date(day.getTime() + Number(h) * 3600e3).toISOString();
  const row = (id, h, direction, amount, notes, inv) => ({ id, store_id: STORE, operation_type: inv ? 'فاتورة شراء' : 'مصروف', direction, amount, currency: 'USD', notes, created_at: T(h), cash_movement_id: inv ? 'c' + id : null, cm: inv ? { invoice_id: inv } : null });
  await install(page, { db: base({ daily_cash_log: [
    row('r0', '06', 'in', 5000, 'رصيد', null),
    row('r1', '07', 'out', 1500, 'دفع فاتورة شراء PINV-5', 'p5'),
    row('r2', '08', 'in', 1500, 'حذف قيمة فاتورة PINV-5 (قبل التعديل)', 'p5'),
    row('r3', '08', 'out', 1700, 'إضافة قيمة فاتورة PINV-5 (بعد التعديل)', 'p5'),
    row('r4', '09', 'out', 300, 'دفع فاتورة شراء PINV-6', 'p6'),
    row('r5', '09', 'in', 300, 'حذف قيمة فاتورة PINV-6 (قبل التعديل)', 'p6') ] }) });
  await page.goto('/daily-cashbox-ar.html');
  const body = page.locator('#cashbox-table-body');
  await expect(body).toContainText('PINV-5');
  await expect(body).toContainText('1,700.00');
  await expect(body).not.toContainText('قبل التعديل');
  await expect(body).not.toContainText('PINV-6');          // cancelled the same day: gone
  await expect(body.locator('td', { hasText: 'فاتورة شراء' })).toHaveCount(1);
  await expect(page.locator('#balances-by-currency')).toContainText('3,300.00');
  expect(errs).toEqual([]);
});

test('editing a purchase without changing its amount posts nothing to the cash', async ({ page }) => {
  const calls = await install(page, { db: base({
    invoices: [{ id: 'p5', store_id: STORE, invoice_number: 'PINV-5', type: 'buyRetail', status: 'paid', payment_method: 'cash', total_amount: 1500, amount_paid: 1500, created_at: '2026-10-01T07:00:00Z' }],
    invoice_items: [{ id: 'it1', invoice_id: 'p5', karat: 21, weight_grams: 20, line_total: 1500, description: 'كسر' }],
    customers: [], pieces: [] }) });
  await page.goto('/invoice-edit-ar.html?id=p5');
  await expect(page.locator('#lockedNumber')).toHaveText('PINV-5');
  await expect(page.locator('#newTotal')).toContainText('1,500');
  page.on('dialog', d => d.accept());
  await page.click('#save-btn');
  await expect.poll(() => calls.some(c => c.method === 'PATCH' && c.name === 'invoices')).toBe(true);
  await page.waitForTimeout(500);
  expect(calls.filter(c => c.method === 'POST' && c.name === 'cash_movements').map(c => c.body)).toEqual([]);
});

test('buying from an individual hides the trader-invoice photo button', async ({ page }) => {
  await install(page, { generic: true, db: base({ traders: [], gold_prices: [] }) });
  await page.goto('/create-invoice-v2-ar.html');
  await expect(page.locator('#ocr-photo-btn')).not.toHaveClass(/hidden/);
  await page.click('#tabRetail');
  await expect(page.locator('#ocr-photo-btn')).toHaveClass(/hidden/);
  await page.click('#tabTrader');
  await expect(page.locator('#ocr-photo-btn')).not.toHaveClass(/hidden/);
});
