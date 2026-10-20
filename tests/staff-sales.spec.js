// Sales count for a staff member (البائع), staff without a login, the staff sales report,
// and what employees see without permissions (today only, no traders, no profit).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const ago = h => new Date(Date.now() - h * 36e5).toISOString();
const db = (role = 'owner', permissions = {}) => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD', vat_rate: 0 }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role, permissions, full_name: 'بشار' },
          { id: 's2', store_id: STORE, role: 'staff', permissions: {}, full_name: 'رامي', user_id: null }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
});

test('sale screen: the owner picks the seller, the choice goes to the server with the sale', async ({ page }) => {
  await install(page, { db: db() });
  const sent = [];
  page.on('request', r => { if (r.method() !== 'GET' && /supabase\.co/.test(r.url())) sent.push(r.headers()['x-gm-seller'] || null); });
  await page.goto('/new-sale-ar.html');
  const sel = page.locator('#ns-seller select');
  await expect(sel).toBeVisible();
  await expect(sel.locator('option')).toHaveCount(2);
  await expect(sel.locator('option[value="s2"]')).toContainText('بدون حساب');
  await sel.selectOption('s2');
  expect(await page.evaluate(() => window.gmSeller)).toBe('s2');
  await page.evaluate(() => goldmindClient.rpc('post_sale_invoice', { p: {} }));
  expect(sent.pop()).toBe('s2');
  await sel.selectOption(STAFF);                                           // back to me: nothing is sent
  expect(await page.evaluate(() => window.gmSeller)).toBeNull();
});

test('sale screen: an employee without «تحديد البائع» sees no seller choice', async ({ page }) => {
  await install(page, { db: db('staff', { create_invoice: true }) });
  await page.goto('/new-sale-ar.html');
  await expect(page.locator('#ns-seller')).toHaveClass(/\bhidden\b/);
  expect(await page.evaluate(() => window.gmSeller)).toBeNull();
});

test('staff sales report: sales by seller (or by who entered them), returns against the seller, weight per karat and profit', async ({ page }) => {
  const d = db();
  d.invoices = [
    { id: 'i1', store_id: STORE, type: 'sale', status: 'paid', invoice_number: 'INV-1', created_at: ago(2), salesperson_id: 's2', created_by: STAFF, customer: { name: 'هلا' } },
    { id: 'i2', store_id: STORE, type: 'sale', status: 'paid', invoice_number: 'INV-2', created_at: ago(1), salesperson_id: null, created_by: STAFF },
    { id: 'r1', store_id: STORE, type: 'return', status: 'paid', invoice_number: 'RET-1', created_at: ago(0.5), salesperson_id: 's2', created_by: STAFF },
  ];
  d.invoice_items = [
    { id: 'a', invoice_id: 'i1', karat: 18, weight_grams: 10, line_total: 1000, gold_price_per_gram: 80 },
    { id: 'b', invoice_id: 'i2', karat: 21, weight_grams: 4, line_total: 500, gold_price_per_gram: 100 },
    { id: 'c', invoice_id: 'r1', karat: 18, weight_grams: 2, line_total: 200, gold_price_per_gram: 80 },
  ];
  d.gold_prices = [];
  await install(page, { db: d });
  await page.goto('/staff-sales-ar.html');
  const rami = page.locator('#ssTable tr[data-sid="s2"]');
  await expect(rami).toContainText('رامي');
  await expect(rami).toContainText('1 − 1 مرتجع');
  await expect(rami).toContainText('8.00');                                 // 10 − 2 g of 18K
  await expect(rami).toContainText('800.00');                               // 1000 − 200
  await expect(rami).toContainText('160.00');                               // (1000 − 800) − (200 − 160)
  await expect(page.locator(`#ssTable tr[data-sid="${STAFF}"]`)).toContainText('500.00');
  await rami.click();
  await expect(page.locator('#ssDetail')).toContainText('INV-1');
  await expect(page.locator('#ssDetail')).toContainText('RET-1');
});

test('staff sales report: employees without the profit right cannot open it', async ({ page }) => {
  await install(page, { db: db('staff', {}) });
  await page.goto('/staff-sales-ar.html');
  await expect(page.locator('#no-access')).not.toHaveClass(/\bhidden\b/);
});

test('add a staff member without a login: listed by name, a login can be made later', async ({ page }) => {
  const calls = await install(page, { db: db() });
  await page.goto('/staff-permissions-ar.html');
  await expect(page.locator('#staff-list')).toContainText('موظف بدون حساب دخول');
  await expect(page.locator('#staff-list button', { hasText: 'إنشاء حساب دخول له' })).toHaveCount(1);
  await page.click('#direct-add-toggle-btn');
  await page.fill('#direct-name', 'سامر');
  await page.check('#direct-no-login');
  await expect(page.locator('#direct-login-fields')).toHaveClass(/\bhidden\b/);
  await page.click('#direct-add-btn');
  await expect.poll(() => calls.filter(c => c.method === 'POST' && c.name === 'staff').length).toBe(1);
  const body = JSON.parse(calls.find(c => c.method === 'POST' && c.name === 'staff').body);
  expect(body).toMatchObject({ full_name: 'سامر', role: 'staff', store_id: STORE });
  expect(body.user_id).toBeUndefined();
});

test('employee without past days / traders: invoices list is today only and has no trader documents', async ({ page }) => {
  const d = db('staff', { view_invoices: true });
  d.invoices = [
    { id: 'i1', store_id: STORE, type: 'sale', status: 'paid', invoice_number: 'INV-TODAY', created_at: ago(0.2), total_amount: 100 },
    { id: 'i2', store_id: STORE, type: 'buyTrader', status: 'paid', invoice_number: 'PINV-TRADER', trader_id: 't1', created_at: ago(0.1), total_amount: 50 },
  ];
  d.invoice_items = []; d.repair_tickets = []; d.trader_movements = [{ id: 'm1', store_id: STORE, trader_id: 't1', source: 'cash_out', created_at: ago(0.1) }];
  d.stock_vouchers = []; d.customer_debts = [];
  await install(page, { db: d });
  await page.goto('/invoices-list-ar.html');
  await expect(page.locator('#fromDate')).toBeDisabled();
  await expect(page.locator('#results-list')).toContainText('INV-TODAY');
  await expect(page.locator('#results-list')).not.toContainText('PINV-TRADER');
  await expect(page.locator('#results-list')).not.toContainText('سند كاش');
});

test('employee without «عرض التجار» cannot open the traders page', async ({ page }) => {
  await install(page, { db: db('staff', {}) });
  await page.goto('/ledger-ar.html');
  await expect(page.locator('body')).toContainText('ليست لديك صلاحية عرض التجار');
});
