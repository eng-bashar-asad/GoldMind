// Exchange (تبديل): pick the returned piece, scan the new one, type the difference + currency + how it was paid.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('exchange page sends the typed difference in its currency', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  let sent = null;
  await install(page, { generic: true, rpc: { post_sale_exchange: a => { sent = a.p; return { body: { id: 'n1', invoice_number: 'INV-50' } }; } }, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD', secondary_currency: 'SYP', secondary_currency_rate: 13000 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'نغم' }],
    invoices: [{ id: 's1', store_id: STORE, invoice_number: 'INV-26', type: 'sale', status: 'paid', payment_method: 'cash', customer_id: 'c1', total_amount: 796.15, amount_paid: 796.15, created_at: '2026-10-05T10:00:00Z' }],
    invoice_items: [{ id: 'it1', invoice_id: 's1', piece_id: 'p118', barcode: '000118', karat: 18, weight_grams: 6.19, line_total: 796.15, description: 'خاتم' }],
    pieces: [{ id: 'p100', store_id: STORE, barcode: '000100', status: 'available', weight_grams: 10.45, karat: 18, description_ar: 'إسوارة' }]
  } });
  page.on('dialog', d => d.accept());
  await page.goto('/exchange-ar.html?id=s1');
  await expect(page.locator('#orig-number')).toHaveText('INV-26');
  await expect(page.locator('.ex-old input')).toBeChecked();      // the only piece is pre-selected
  await page.fill('#bc-input', '000100');
  await page.click('text=إضافة');
  await expect(page.locator('.ex-new')).toContainText('000100');
  await page.fill('#diff-amount', '530');
  await page.selectOption('#diff-method', 'account');
  await expect(page.locator('#ex-summary')).toContainText('1,326.15');
  await expect(page.locator('#ex-summary')).toContainText('يدخل الصندوق: لا شيء');
  await page.selectOption('#diff-cur', 'SYP');
  await expect(page.locator('#diff-rate')).toHaveValue('13000');
  await page.fill('#diff-amount', '6890000');
  await page.selectOption('#diff-method', 'partial');
  await expect(page.locator('#paid-amount')).toBeVisible();
  await page.fill('#paid-amount', '5000000');
  await expect(page.locator('#ex-summary')).toContainText('وارد 5,000,000 SYP');
  await expect(page.locator('#ex-summary')).toContainText('يبقى دين على الزبون: 1,890,000 SYP');
  await page.selectOption('#diff-method', 'cash');
  await expect(page.locator('#ex-summary')).toContainText('1,326.15');
  await expect(page.locator('#ex-summary')).toContainText('وارد 6,890,000 SYP');
  await page.click('#ex-btn');
  await expect.poll(() => sent).not.toBeNull();
  expect(sent).toMatchObject({ original_invoice_id: 's1', item_ids: ['it1'], new_piece_ids: ['p100'], diff_dir: 'in', diff_amount: 6890000, diff_currency: 'SYP', diff_rate: 13000, diff_method: 'cash' });
  await expect(page).toHaveURL(/invoice-print-ar\.html\?id=n1/);
  expect(errs).toEqual([]);
});

test('exchange invoice prints the returned piece under its own heading and the difference without a minus', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'نغم' }],
    invoices: [{ id: 'x1', store_id: STORE, invoice_number: 'INV-32', type: 'sale', is_exchange: true, related_invoice_id: 's1', status: 'paid', payment_method: 'cash', customer_id: 'c1', total_amount: 530, amount_paid: 530, created_at: '2026-10-08T10:00:00Z' },
               { id: 's1', store_id: STORE, invoice_number: 'INV-26', type: 'sale', status: 'paid', customer_id: 'c1', total_amount: 796.15, created_at: '2026-10-05T10:00:00Z' }],
    invoice_items: [{ id: 'a', invoice_id: 'x1', piece_id: 'p100', barcode: '000100', karat: 18, weight_grams: 10.45, line_total: 1326.15, description: 'إسوارة' },
                    { id: 'b', invoice_id: 'x1', piece_id: 'p118', barcode: '000118', karat: 18, weight_grams: 6.19, line_total: -796.15, description: 'خاتم', returned_item_id: 'it1' }]
  } });
  await page.goto('/invoice-print-ar.html?id=x1');
  await expect(page.locator('#doc-type-ar')).toHaveText('فاتورة تبديل');
  const heads = page.locator('#items-body .ex-head');
  await expect(heads).toHaveText(['القطعة المُرجَعة', 'القطعة الجديدة']);
  await expect(page.locator('#items-body')).not.toContainText('-796');
  await expect(page.locator('#items-body')).toContainText('796.15');
  await expect(page.locator('#sum-total-label')).toHaveText('الفرق المستحق على الزبون');
  await expect(page.locator('#sum-total')).toContainText('530');
  await expect(page.locator('#doc-related-invoice')).toContainText('INV-26');
});
