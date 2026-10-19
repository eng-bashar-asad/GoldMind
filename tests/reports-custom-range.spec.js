// Reports page: choosing "مخصص" fills this month and loads it, instead of leaving today's zeros on screen.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('custom range starts from this month and shows its sales', async ({ page }) => {
  const now = new Date(), day = s => s.toISOString();
  const earlier = new Date(now.getFullYear(), now.getMonth(), 1, 12).toISOString();
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD', vat_rate: 0 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'b' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [{ id: 'i1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', total_amount: 2700, created_at: earlier }],
    invoice_items: [], gold_prices: [], pieces: [], gold_stock_lots: [],
  } });
  await page.goto('/reports-ar.html');
  await page.locator('[data-period="custom"]').click();
  await expect(page.locator('#customFrom')).not.toHaveValue('');
  await expect(page.locator('#customTo')).not.toHaveValue('');
  await expect(page.locator('#stat-total-sales')).toHaveText('2,700.00', { timeout: 15000 });
});

test('this month: one bar per day; a day keeps only its invoices in the table, with a totals row', async ({ page }) => {
  const now = new Date();
  const d1 = new Date(now.getFullYear(), now.getMonth(), 1, 12).toISOString();
  const d2 = new Date(now.getFullYear(), now.getMonth(), Math.min(2, now.getDate()), 15).toISOString();
  await install(page, { db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD', vat_rate: 0 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'b' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [{ id: 'i1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', payment_method: 'cash', total_amount: 2700, created_at: d1, customer: { name: 'ريما' } },
               { id: 'i2', store_id: STORE, invoice_number: 'INV-2', type: 'sale', status: 'paid', payment_method: 'credit', total_amount: 300, created_at: d2 }],
    invoice_items: [], gold_prices: [], pieces: [], gold_stock_lots: [], trader_movements: [], expense_entries: [],
  } });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/reports-ar.html');
  await page.locator('[data-period="month"]').click();
  await expect(page.locator('#invoices-count')).toHaveText('2', { timeout: 15000 });
  await expect(page.locator('#rp-chart-box')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#rp-chart .rp-day')).toHaveCount(now.getDate());
  await expect(page.locator('#invoices-tbody')).toContainText('ريما');
  await expect(page.locator('#invoices-tfoot')).toContainText('3,000.00');
  await page.locator('#rp-chart .rp-day').first().click();
  if (now.getDate() > 1) {
    await expect(page.locator('#invoices-count')).toHaveText('1');
    await expect(page.locator('#invoices-tfoot')).toContainText('2,700.00');
  }
  await page.click('#rp-day-clear');
  await expect(page.locator('#invoices-count')).toHaveText('2');
});
