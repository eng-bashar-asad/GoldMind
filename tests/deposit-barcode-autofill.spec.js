// Deposit (عربون): a barcode fills the piece's details; the deposit can stay out of the cashbox.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const base = extra => ({
  stores: [{ id: STORE, name: 'محل الاختبار', currency: 'USD', address: 'دمشق', phone: '+963 11 000' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  ...extra
});

test('deposit: barcode fills the piece, price stays empty, cashbox option is sent', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const deposits = [];
  const calls = await install(page, {
    db: base({
      customers: [{ id: 'cu1', store_id: STORE, name: 'هلا الهفل', phone: '0999' }],
      pieces: [{ id: 'p1', store_id: STORE, barcode: '000709', piece_type: 'خاتم', karat: 18, weight_grams: 9.21, status: 'available' }],
      customer_deposits: deposits
    }),
    rpc: { create_customer_deposit: a => {
      deposits.push({ id: 'd1', store_id: STORE, deposit_number: 'DEP-000001', customer_id: 'cu1', amount: a.p.amount, method: a.p.method,
        items: a.p.items, notes: null, status: 'active', created_at: '2026-10-17T10:00:00Z', customer: { name: 'هلا الهفل', phone: '0999' }, staff: { full_name: 'بشار' } });
      return { body: { id: 'd1', deposit_number: 'DEP-000001' } };
    } }
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/deposits-ar.html?customer=cu1');
  await page.fill('#amount-input', '200');
  await page.fill('[data-f="barcode"]', '709');
  await page.locator('[data-f="barcode"]').dispatchEvent('change');
  await expect(page.locator('[data-f="description"]')).toHaveValue('خاتم · 18K · 9.21 غ');
  await expect(page.locator('[data-f="karat"]')).toHaveValue('18');
  await expect(page.locator('[data-f="price"]')).toHaveValue('');
  await page.uncheck('#to-cashbox');
  await page.click('#save-btn');
  await expect(page.locator('#voucher')).toContainText('DEP-000001');
  const sent = JSON.parse(calls.find(c => c.name === 'create_customer_deposit').body).p;
  expect(sent).toMatchObject({ customer_id: 'cu1', amount: 200, to_cashbox: false, items: [{ barcode: '000709', karat: 18, weight: 9.21 }] });
  expect(errs).toEqual([]);
});
