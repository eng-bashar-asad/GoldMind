// Internal name for the company list / top of screen; invoices keep the store name.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

function setup(page, store) {
  return install(page, {
    db: {
      stores: [{ id: STORE, name: 'Ahmad Al Khayat Jewellery', currency: 'AED', ...store }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'b' }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      invoices: [{ id: 'inv1', store_id: STORE, invoice_number: 'INV-2026-000001', type: 'sale', total_amount: 100, vat_amount: 0, status: 'paid', created_at: '2026-10-14T10:00:00Z', payment_method: 'cash', customer_id: null }],
      invoice_items: [], customers: [], gold_prices: [], pieces: [], traders: [],
    },
  });
}

test('company settings saves the internal name and shows it in the badge', async ({ page }) => {
  const calls = await setup(page, { display_name: null });
  await page.goto('/company-settings-ar.html');
  await expect(page.locator('#display-name-wrap')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#active-store-badge')).toHaveText('Ahmad Al Khayat Jewellery');
  await page.locator('#store-display-name').fill('  الفارس ');
  await page.locator('button:has-text("حفظ البيانات")').first().click();
  await expect.poll(() => calls.find(c => c.method === 'PATCH' && c.name === 'stores')).toBeTruthy();
  const patch = JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'stores').body);
  expect(patch.display_name).toBe('الفارس');
  expect(patch.name).toBe('Ahmad Al Khayat Jewellery');
  await expect(page.locator('#active-store-badge')).toHaveText('الفارس');
});

test('before the column exists the field is hidden and not sent', async ({ page }) => {
  const calls = await setup(page, {});
  await page.goto('/company-settings-ar.html');
  await expect(page.locator('#display-name-wrap')).toHaveClass(/\bhidden\b/);
  await page.locator('button:has-text("حفظ البيانات")').first().click();
  await expect.poll(() => calls.find(c => c.method === 'PATCH' && c.name === 'stores')).toBeTruthy();
  expect(JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'stores').body)).not.toHaveProperty('display_name');
});

test('home shows the internal name; the invoice keeps the store name', async ({ page }) => {
  await setup(page, { display_name: 'الفارس' });
  await page.goto('/index-ar.html');
  await expect(page.locator('#storeNameEl')).toHaveText('الفارس');
  await page.goto('/invoice-print-ar.html?id=inv1');
  await expect(page.locator('#store-name')).toHaveText('Ahmad Al Khayat Jewellery');
});
