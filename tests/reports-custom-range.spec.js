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
