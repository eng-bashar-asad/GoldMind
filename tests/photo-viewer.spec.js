// Tap a photo on the invoice: it opens large over the page; ✕ or a tap outside closes it.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('photo viewer opens and closes', async ({ page }) => {
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'x' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.route(/example\.com/, r => r.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"/>' }));
  await page.goto('/customers-ar.html');
  await page.evaluate(() => { const i = document.createElement('img'); i.id = 't'; i.src = 'https://example.com/a.svg'; i.onclick = () => gmPhotoViewer(i.src); i.style.cssText = 'width:40px;height:40px'; document.body.prepend(i); });
  await page.click('#t');
  const v = page.locator('#gm-photo-viewer');
  await expect(v).toBeVisible();
  await expect(v.locator('a[data-open]')).toHaveAttribute('href', 'https://example.com/a.svg');
  await v.locator('[data-close]').click();
  await expect(v).toBeHidden();
  await page.click('#t');
  await page.mouse.click(5, 400);                          // outside the photo
  await expect(v).toBeHidden();
  await page.click('#t');
  await page.keyboard.press('Escape');
  await expect(v).toBeHidden();
});

test('main cashbox: a movement linked to an invoice opens it', async ({ page }) => {
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'x', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    cash_movements: [{ id: 'm1', store_id: STORE, box: 'main', direction: 'in', amount: 4500, currency: 'USD', description: 'تحصيل فاتورة بيع INV-9', created_at: new Date().toISOString(), invoice_id: 'inv9', staff: { full_name: 'بشار' } }] } });
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await page.goto('/main-cashbox-ar.html');
  await page.waitForTimeout(1500);
  await expect(page.locator('a[href="invoice-print-ar.html?id=inv9"]')).toContainText('فتح الفاتورة');
  expect(errs).toEqual([]);
});

test('invoice payment line: part payment names only what was used', async ({ page }) => {
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'x' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.goto('/invoice-print-ar.html');
  await page.waitForFunction(() => typeof gmPaymentLabel === 'function');
  const r = await page.evaluate(() => {
    const st = { currency: 'USD' };
    return [gmPaymentLabel({ payment_method: 'mixed', cash_paid_amount: 3000, bank_paid_amount: 0 }, st),
            gmPaymentLabel({ payment_method: 'mixed', cash_paid_amount: 0, bank_paid_amount: 500 }, st),
            gmPaymentLabel({ payment_method: 'mixed', cash_paid_amount: 100, bank_paid_amount: 50 }, st),
            gmPaymentLabel({ payment_method: 'cash' }, st)];
  });
  expect(r).toEqual(['جزئي — نقداً 3,000 USD', 'جزئي — فيزا / بنك 500 USD', 'جزئي — نقداً 100 USD + فيزا / بنك 50 USD', 'نقداً']);
});
