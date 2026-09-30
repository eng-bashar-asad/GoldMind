// Phase 2: expenses with staff-defined types (gifts are one type, several pieces at once),
// deposit vouchers, customer payments through the server (cashbox + oldest invoice first).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const base = extra => ({
  stores: [{ id: STORE, name: 'محل الاختبار', currency: 'USD', address: 'دمشق', phone: '+963 11 000' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  ...extra
});

test('expenses: pick a type, record it into the daily cashbox; gifts take several pieces', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const P = (id, bc) => ({ id, store_id: STORE, barcode: bc, status: 'available', karat: 18, weight_grams: 10, accounting_weight_grams: 9.5, cost_fabrication_per_gram: 2, piece_type: 'خاتم' });
  const gifted = [];
  const calls = await install(page, {
    db: base({
      expense_categories: [{ id: 'c1', store_id: STORE, name: 'كهرباء' }, { id: 'c2', store_id: STORE, name: 'هدايا' }],
      gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 100 }],
      pieces: [P('p1', '000001'), P('p2', '000002')],
      expense_entries: [], inventory_gifts: []
    }),
    rpc: {
      record_expense: () => ({ body: 'e1' }),
      gift_out_piece: a => { gifted.push(a.target_piece_id); return { body: 'g' }; }
    }
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/expense-entry-ar.html');
  await page.click('.cat-chip:has-text("كهرباء")');
  await page.fill('#amount-input', '250');
  await page.fill('#desc-input', 'فاتورة أيلول');
  await page.click('#save-btn');
  await expect(page.locator('#save-success')).toContainText('خُصم من الصندوق اليومي');
  const rec = JSON.parse(calls.find(c => c.name === 'record_expense').body).p;
  expect(rec).toMatchObject({ category_id: 'c1', amount: 250, from_daily_cashbox: true, description: 'فاتورة أيلول' });

  await page.click('.cat-chip:has-text("هدايا")');
  await expect(page.locator('#money-form')).toHaveClass(/hidden/);
  for (const bc of ['1', '2']) { await page.fill('#barcode-input', bc); await page.press('#barcode-input', 'Enter'); await expect(page.locator('#basket > div')).toHaveCount(Number(bc)); }
  // 9.5 g × 100 + 9.5 × 2 = 969 each
  await expect(page.locator('#basket-total')).toContainText('1,938.00');
  await expect(page.locator('#gift-btn')).toHaveText('إخراج 2 قطع كهدية');
  await page.fill('#recipient-input', 'عميل مميز');
  page.on('dialog', d => d.accept());
  await page.click('#gift-btn');
  await expect(page.locator('#save-success')).toContainText('هدايا');
  expect(gifted).toEqual(['p1', 'p2']);
  expect(errs).toEqual([]);
});

test('expenses: staff can add their own expense type', async ({ page }) => {
  const calls = await install(page, {
    db: base({ expense_categories: [], expense_entries: [], inventory_gifts: [], gold_prices: [] }),
    rpc: { save_expense_category: () => ({ body: 'new1' }) }
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/expense-entry-ar.html');
  await page.click('.cat-chip:has-text("+ نوع جديد")');
  await page.fill('#new-cat-name', 'إيجار');
  await page.click('button:has-text("إضافة")');
  await expect.poll(() => calls.some(c => c.name === 'save_expense_category')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'save_expense_category').body)).toMatchObject({ p_name: 'إيجار' });
});

test('old gifts page opens the gifts part of the expenses page', async ({ page }) => {
  await install(page, { db: base({ expense_categories: [], expense_entries: [], inventory_gifts: [], gold_prices: [] }) });
  await page.goto('/gifts-ar.html');
  await page.waitForURL(/expense-entry-ar\.html\?type=gifts/);
  await expect(page.locator('#gift-form')).not.toHaveClass(/hidden/);
});

test('deposit: voucher with the pieces, saved through the server', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const deposits = [];
  const calls = await install(page, {
    db: base({ customers: [{ id: 'cu1', store_id: STORE, name: 'هلا الهفل', phone: '0999' }], customer_deposits: deposits }),
    rpc: { create_customer_deposit: a => {
      deposits.push({ id: 'd1', store_id: STORE, deposit_number: 'DEP-000001', customer_id: 'cu1', amount: a.p.amount, method: a.p.method,
        items: a.p.items, notes: a.p.notes, status: 'active', created_at: '2026-09-30T10:00:00Z', customer: { name: 'هلا الهفل', phone: '0999' }, staff: { full_name: 'بشار' } });
      return { body: { id: 'd1', deposit_number: 'DEP-000001' } };
    } }
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/deposits-ar.html?customer=cu1');
  await expect(page.locator('#customer-input')).toHaveValue('هلا الهفل — 0999');
  await page.fill('#amount-input', '200');
  await page.fill('[data-f="description"]', 'طقم ديور');
  await page.fill('[data-f="price"]', '1500');
  await page.click('#save-btn');
  const v = page.locator('#voucher');
  await expect(v).toContainText('سند قبض عربون');
  await expect(v).toContainText('DEP-000001');
  await expect(v).toContainText('طقم ديور');
  await expect(v).toContainText('1,300.00');               // remaining at pickup
  const sent = JSON.parse(calls.find(c => c.name === 'create_customer_deposit').body).p;
  expect(sent).toMatchObject({ customer_id: 'cu1', amount: 200, method: 'cash', items: [{ description: 'طقم ديور', price: 1500 }] });
  expect(errs).toEqual([]);
});

test('customer payment goes through the server function (cashbox + invoices)', async ({ page }) => {
  const calls = await install(page, {
    db: base({ customers: [{ id: 'cu1', store_id: STORE, name: 'ريما شالاتي', phone: '0999' }],
      customer_debts: [{ id: 'm1', store_id: STORE, customer_id: 'cu1', movement_type: 'debt_increase', cash_amount: 3900, gold_grams_24k: 0, created_at: '2026-09-28T10:00:00Z', invoice: { invoice_number: 'INV-5' } }],
      customer_phones: [], company_kyc_documents: [] }),
    rpc: { record_customer_payment: () => ({ body: { ok: true } }) }
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/customer-debts-ar.html');
  await expect(page.locator('#customers-list')).toContainText('ريما شالاتي');
  await page.evaluate(() => showCustomerDetail('cu1'));
  await page.evaluate(() => toggleSettleForm());
  await page.fill('#settle-amount', '3900');
  await page.click('#settle-btn');
  await expect.poll(() => calls.some(c => c.name === 'record_customer_payment')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'record_customer_payment').body)).toMatchObject({ p_customer: 'cu1', p_amount: 3900, p_method: 'cash' });
  expect(calls.some(c => c.method === 'POST' && c.name === 'cash_movements')).toBe(false);
});
