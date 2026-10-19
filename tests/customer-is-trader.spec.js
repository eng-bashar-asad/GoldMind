// A name that is already a trader is not added again as a customer.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('adding a customer with a trader\'s name points to the trader account', async ({ page }) => {
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [], traders: [{ id: 't1', store_id: STORE, name: 'حمدي الخياط' }],
  } });
  await page.goto('/customer-add-ar.html');
  await page.fill('#customer-name', 'حمدي الخياط');
  await page.check('#kyc-declaration');
  await page.click('#save-btn');
  await expect(page.locator('#save-message')).toContainText('مسجّل كتاجر');
  await expect(page.locator('#save-message a[href="ledger-ar.html?trader=t1"]')).toBeVisible();
  expect(calls.some(c => c.method === 'POST' && c.name === 'customers')).toBe(false);
});

test('«حفظ وبيع»: the new customer is saved and the sale opens with him already picked', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [], traders: [], customer_debts: [], pieces: [], gold_prices: [], diamond_pieces: [], gold_stock_lots: [],
  } });
  // the fake backend answers inserts with nothing: hand back the new row and keep it for the sale screen
  const saved = [];
  await page.route(/rest\/v1\/customers/, async route => {
    const req = route.request();
    if (req.method() === 'POST') { const row = { ...JSON.parse(req.postData()), id: 'cnew' }; saved.push(row); return route.fulfill({ status: 201, json: row }); }
    if (new URL(req.url()).searchParams.get('id') === 'eq.cnew') return route.fulfill({ json: saved[0] });
    return route.fallback();
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/customer-add-ar.html');
  await expect(page.locator('#cf-more')).not.toHaveAttribute('open', '');      // optional details folded
  await page.fill('#customer-name', 'سامر حداد');
  await page.fill('#customer-phone', '0501234567');
  await page.check('#kyc-declaration');
  await page.click('#save-sell-btn');
  await page.waitForURL(/new-sale-ar\.html\?customer=cnew/);
  await expect(page.locator('#customer-selected-name')).toHaveText('سامر حداد');
});
