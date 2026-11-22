// بشار 2026-11-22: a purchase (scrap or anything else) paid in cash with several currencies.
// The rows must add up to the invoice total; they go to the server as pay_breakdown.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('cash purchase split between USD and SYP', async ({ page }) => {
  const posts = {};
  await install(page, {
    db: {
      stores: [{ id: STORE, currency: 'USD', name: 'محل', secondary_currency: 'SYP', secondary_currency_rate: 10000 }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      gold_prices: [{ store_id: STORE, karat: 21, price_per_gram: 100 }],
      traders: [],
    },
    rpc: { post_purchase_invoice: (args) => { posts.rpc = args; return { body: { id: 'inv-mc', invoice_number: 'PINV-2026-000011' } }; } },
  });
  page.on('dialog', d => d.accept());
  await page.goto('/create-invoice-v2-ar.html');
  await page.click('#tabRetail');
  await page.fill('#retail-name', 'زبون');
  await page.selectOption('#manual-karat', '21');
  await page.fill('#manual-weight', '12.24');
  await page.fill('#manual-price', '1205');
  await page.click('button[onclick="addManualToCart()"]');

  await page.click('#split-toggle');
  await expect(page.locator('#split-box')).not.toHaveClass(/\bhidden\b/);
  const amounts = page.locator('#split-rows input[aria-label="المبلغ"]');
  await expect(amounts).toHaveCount(2); // USD + SYP
  await expect(page.locator('#split-rows input[aria-label="سعر الصرف"]')).toHaveValue('10000');
  await amounts.nth(0).fill('1000');
  await expect(page.locator('#split-rem')).toContainText('205.00');

  // not adding up → not saved
  await page.click('#save-invoice-btn');
  await expect(page.locator('#save-message')).toContainText('المتبقي');
  expect(posts.rpc).toBeUndefined();

  await amounts.nth(1).fill('2050000'); // 205 USD at 10,000
  await expect(page.locator('#split-rem')).toContainText('0.00');
  await page.click('#save-invoice-btn');
  await expect.poll(() => posts.rpc && posts.rpc.p.pay_breakdown, { timeout: 8000 }).toEqual([
    { currency: 'USD', amount: 1000, rate: 1 }, { currency: 'SYP', amount: 2050000, rate: 10000 },
  ]);
  expect(posts.rpc.p.payment_method).toBe('cash');
});

// بشار 2026-11-22: goods photos — each pick adds more, and a wrong one can be removed
test('purchase goods photos: add more, remove one', async ({ page }) => {
  await install(page, { db: { stores: [{ id: STORE, currency: 'USD', name: 'محل' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], traders: [] } });
  await page.goto('/create-invoice-v2-ar.html');
  const img = n => ({ name: n, mimeType: 'image/jpeg', buffer: Buffer.from([0xff, 0xd8, 0xff, 0xd9]) });
  await page.setInputFiles('#bulk-photos-input', [img('a.jpg'), img('b.jpg')]);
  await page.setInputFiles('#bulk-photos-input', [img('c.jpg')]);
  await expect(page.locator('#bulk-photos-preview img')).toHaveCount(3);
  await page.locator('#bulk-photos-preview button[aria-label="حذف الصورة"]').first().click();
  await expect(page.locator('#bulk-photos-preview img')).toHaveCount(2);
  await expect(page.locator('#bulk-photos-label')).toContainText('2 صورة');
});
