// "الزبائن" in the side menu: retail customers list, search by name or phone, edit button.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('customers page: retail list, search, edit, menu entry', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [
      { id: 'c1', store_id: STORE, name: 'ريما شالاتي', phone: '0944123456', is_company: false },
      { id: 'c2', store_id: STORE, name: 'هلا الهفل', phone: '0955000111', is_company: false },
      { id: 'c3', store_id: STORE, name: 'شركة النور', phone: '', is_company: true } ],
    customer_debts: [{ store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', cash_amount: 500 }, { store_id: STORE, customer_id: 'c2', movement_type: 'debt_decrease', cash_amount: 200 }],
  } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/customers-ar.html');
  await expect(page.locator('#count')).toHaveText('2 زبون');           // retail only by default
  await expect(page.locator('#list')).toContainText('لنا عنده 500.00 USD');
  await expect(page.locator('#list .text-success', { hasText: 'لنا عنده' })).toHaveCount(1); // same colours as the traders
  await page.fill('#q', '0955');
  await expect(page.locator('#count')).toHaveText('1 زبون');
  await expect(page.locator('#list a:has-text("تعديل")')).toHaveAttribute('href', 'customer-edit-ar.html?id=c2');
  await page.fill('#q', '');
  await page.click('.kind[data-k="company"]');
  await expect(page.locator('#list')).toContainText('شركة النور');
  await expect(page.locator('#list')).not.toContainText('ريما');          // companies never mixed with individuals
  await page.click('.kind[data-k="person"]');
  await page.click('.bal[data-b="debt"]');
  await expect(page.locator('#count')).toHaveText('1 زبون');
  await page.click('.bal[data-b="credit"]');
  await expect(page.locator('#count')).toHaveText('1 زبون');
  await expect(page.locator('#list')).toContainText('علينا له 200.00 USD');
  await page.click('.bal[data-b="open"]');
  await expect(page.locator('#count')).toHaveText('2 زبون');
  await page.waitForSelector('#gmNav a[href="customers-ar.html"]', { state: 'attached' });
  expect(await page.locator('#gmNav a[href="customers-ar.html"]').textContent()).toContain('الزبائن');
  expect(await page.locator('#gmNav a[href="ledger-ar.html"]').textContent()).toContain('التجار');
  expect(errs).toEqual([]);
});

test('customer page: all dealings with him (invoices + payments), each opens', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ريما شالاتي', phone: '0944', is_company: false }],
    invoices: [{ id: 'i1', store_id: STORE, customer_id: 'c1', invoice_number: 'INV-1', type: 'sale', status: 'paid', payment_method: 'cash', total_amount: 900, amount_paid: 900, created_at: '2026-10-01T10:00:00Z' },
               { id: 'i2', store_id: STORE, customer_id: 'c1', invoice_number: 'INV-2', type: 'sale', status: 'unpaid', payment_method: 'credit', total_amount: 500, amount_paid: 0, created_at: '2026-10-02T10:00:00Z' }],
    customer_debts: [{ id: 'd1', store_id: STORE, customer_id: 'c1', invoice_id: 'i2', movement_type: 'debt_increase', cash_amount: 500, created_at: '2026-10-02T10:00:00Z' },
                     { id: 'd2', store_id: STORE, customer_id: 'c1', movement_type: 'debt_decrease', source: 'payment', cash_amount: 200, created_at: '2026-10-03T10:00:00Z' }],
    customer_phones: [], company_kyc_documents: [], customer_deposits: []
  } });
  await page.setViewportSize({ width: 390, height: 844 }); // phone cards (the computer shows a statement table)
  await page.goto('/customer-debts-ar.html?open=c1');
  const list = page.locator('#movements-list');
  await expect(list.locator('a[href="invoice-print-ar.html?id=i1"]')).toContainText('INV-1');   // cash sale shows too
  await expect(list.locator('a[href="invoice-print-ar.html?id=i2"]')).toContainText('باقي ديناً');
  await expect(list).toContainText('دفعة من العميل');
  await expect(list.locator('> *')).toHaveCount(3);                                              // invoice debt row not doubled
  expect(errs).toEqual([]);
});

test('customer page on the computer: statement table with running balance, a click shows the row buttons', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'الشارقة', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ريما شالاتي', phone: '0944', is_company: false, nationality: 'سورية' }],
    invoices: [{ id: 'i1', store_id: STORE, customer_id: 'c1', invoice_number: 'INV-1', type: 'sale', status: 'paid', payment_method: 'cash', total_amount: 900, amount_paid: 900, created_at: '2026-10-01T10:00:00Z' },
               { id: 'i2', store_id: STORE, customer_id: 'c1', invoice_number: 'INV-2', type: 'sale', status: 'unpaid', payment_method: 'credit', total_amount: 500, amount_paid: 0, created_at: '2026-10-02T10:00:00Z' }],
    customer_debts: [{ id: 'd1', store_id: STORE, customer_id: 'c1', invoice_id: 'i2', movement_type: 'debt_increase', cash_amount: 500, created_at: '2026-10-02T10:00:00Z' },
                     { id: 'd2', store_id: STORE, customer_id: 'c1', movement_type: 'debt_decrease', source: 'payment', cash_amount: 200, created_at: '2026-10-03T10:00:00Z' }],
    customer_phones: [], company_kyc_documents: [], customer_deposits: []
  } });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/customer-debts-ar.html?open=c1');
  const rows = page.locator('#movements-list tr.cd-row');
  await expect(rows).toHaveCount(3);
  // newest first: payment → balance 300, then INV-2 → 500, then the cash sale → 0
  await expect(rows.nth(0).locator('td').nth(6)).toHaveText('300.00 لنا');
  await expect(rows.nth(1).locator('td').nth(4)).toHaveText('500.00');
  await expect(rows.nth(1).locator('td').nth(6)).toHaveText('500.00 لنا');
  await expect(rows.nth(2).locator('td').nth(6)).toHaveText('0.00');
  await expect(page.locator('#cdCash')).toHaveText('300.00');
  await expect(page.locator('#cdInfoRows')).toContainText('سورية');
  await expect(page.locator('#cdSumRows')).toContainText('1,400.00');
  const extra = page.locator('#movements-list tr.cd-x').first();
  await expect(extra).toHaveClass(/\bhidden\b/);
  await rows.first().click();
  await expect(extra).not.toHaveClass(/\bhidden\b/);
  await expect(extra).toContainText('تعديل الدفعة');
  expect(errs).toEqual([]);
});

test('customers list: totals for us / for them, and how old the oldest unpaid debt is', async ({ page }) => {
  const ago = d => new Date(Date.now() - d * 86400000).toISOString();
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ريما', phone: '0944', is_company: false }, { id: 'c2', store_id: STORE, name: 'هلا', phone: '0955', is_company: false }],
    customer_debts: [
      { store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', cash_amount: 300, created_at: ago(40) },
      { store_id: STORE, customer_id: 'c1', movement_type: 'debt_increase', cash_amount: 200, created_at: ago(10) },
      { store_id: STORE, customer_id: 'c1', movement_type: 'debt_decrease', cash_amount: 300, created_at: ago(5) },
      { store_id: STORE, customer_id: 'c2', movement_type: 'debt_decrease', cash_amount: 80, created_at: ago(2) }],
  } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/customers-ar.html');
  await expect(page.locator('#sumOwed')).toHaveText('200.00 USD');
  await expect(page.locator('#sumCredit')).toHaveText('80.00 USD');
  await expect(page.locator('#list')).toContainText('منذ 10 يوماً');   // the 40-day debt was paid first
  await expect(page.locator('#add-fab')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('nav.gm-bottom-tabs a.gm-tab-on')).toHaveText(/الزبائن/);
});
