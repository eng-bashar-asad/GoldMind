// Buying scrap gold from an individual: goes to the "كسر <karat>" box, cash price
// required, today's value shown as a guide, optional seller ID with photos.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('scrap from an individual lands in the karat scrap box with seller ID', async ({ page }) => {
  const posts = {};
  await install(page, {
    db: {
      stores: [{ id: STORE, currency: 'AED', name: 'محل' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      gold_prices: [{ store_id: STORE, karat: 21, price_per_gram: 300 }, { store_id: STORE, karat: 24, price_per_gram: 342.86 }],
      traders: [],
    },
    rpc: { next_invoice_number: () => ({ body: 'PINV-2026-000009' }) },
  });
  // record writes to the tables and storage this flow uses
  await page.route(/\.supabase\.co\/(rest\/v1\/(invoices|gold_stock_lots|company_kyc_documents|invoice_items)|storage\/v1\/object)/, async (r) => {
    const req = r.request();
    if (req.method() === 'GET') return r.fallback();
    const key = new URL(req.url()).pathname.split('/').slice(-1)[0];
    const isStorage = /storage\/v1\/object/.test(req.url());
    (posts[isStorage ? 'storage' : key] = posts[isStorage ? 'storage' : key] || []).push(isStorage ? req.url() : JSON.parse(req.postData() || '{}'));
    if (isStorage) return r.fulfill({ json: { Key: 'x' } });
    if (key === 'invoices') return r.fulfill({ status: 201, json: { id: 'inv-scrap', invoice_number: 'PINV-2026-000009' } });
    return r.fulfill({ status: 201, json: [] });
  });
  page.on('dialog', d => d.accept());
  await page.goto('/create-invoice-v2-ar.html');
  await page.click('#tabRetail');

  await expect(page.locator('#itemModeBulk')).toHaveText('ذهب كسر');
  await expect(page.locator('#itemModeBulk')).toHaveClass(/active/);
  await expect(page.locator('#manual-price-field')).toBeVisible();
  await expect(page.locator('label[for="manual-price"]')).toHaveText('المبلغ المدفوع للبائع');
  await expect(page.locator('#bulk-fab-per-gram-field')).toBeHidden();

  await page.fill('#retail-name', 'زبون كسر');
  await page.selectOption('#manual-karat', '21');
  await page.fill('#manual-weight', '10');
  await page.fill('#manual-price', '2700');
  await expect(page.locator('#scrap-ref')).toContainText('3,000.00');
  await expect(page.locator('#scrap-ref')).toContainText('90%');
  await expect(page.locator('#itemModeHint')).toContainText('كسر 21');

  // price is required for scrap bought for cash
  await page.fill('#manual-price', '');
  await page.click('button[onclick="addManualToCart()"]');
  await expect(page.locator('#manual-price')).toHaveClass(/border-error/);
  await page.fill('#manual-price', '2700');
  await page.click('button[onclick="addManualToCart()"]');

  await page.selectOption('#seller-id-type', 'passport');
  await expect(page.locator('#seller-id-front-label')).toHaveText('صفحة البيانات');
  await page.fill('#seller-id-number', 'N1234567');
  await page.setInputFiles('#seller-id-front', { name: 'p1.jpg', mimeType: 'image/jpeg', buffer: Buffer.from([0xff, 0xd8, 0xff, 0xd9]) });
  await page.setInputFiles('#seller-id-back', { name: 'p2.jpg', mimeType: 'image/jpeg', buffer: Buffer.from([0xff, 0xd8, 0xff, 0xd9]) });

  await page.click('#save-invoice-btn');
  await expect.poll(() => (posts.company_kyc_documents || []).length, { timeout: 10000 }).toBe(2);

  const inv = posts.invoices[0];
  expect(inv).toMatchObject({ type: 'buyRetail', counterparty_name: 'زبون كسر', seller_id_type: 'passport', seller_id_number: 'N1234567', total_amount: 2700 });
  const lots = posts.gold_stock_lots[0];
  const lot = Array.isArray(lots) ? lots[0] : lots;
  expect(lot).toMatchObject({ karat: 21, weight_grams_total: 10, box_name: 'كسر 21', source_invoice_id: 'inv-scrap' });
  expect(posts.storage.every(u => u.includes('company-kyc-documents') && u.includes('purchase-inv-scrap'))).toBe(true);
  const docs = posts.company_kyc_documents.map(d => (Array.isArray(d) ? d[0] : d));
  expect(docs.map(d => d.document_category).sort()).toEqual(['seller_id_back', 'seller_id_front']);
  expect(docs.every(d => d.owner_type === 'invoice' && d.owner_id === 'inv-scrap')).toBe(true);
});
