// Security audit R1 fixes that live in the pages: username login no longer looks up the
// email without the password, and every CDN script is pinned with an integrity hash.
const { test, expect } = require('@playwright/test');
const fs = require('fs'), path = require('path');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('username login sends the password with the lookup and shows one message for any mistake', async ({ page }) => {
  const asked = [];
  const calls = await install(page, { db: { stores: [{ id: STORE, name: 'محل' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] },
    rpc: { login_email_for: (b) => { asked.push(b); return { body: null }; } } });
  await page.goto('/login-entry-ar.html?mode=quick');
  await page.evaluate(() => goToStep('quick'));
  await page.fill('#quickIdentifier', 'bashar');
  await page.fill('#quickPassword', 'secret-1');
  await page.click('#quickSubmitBtn');
  await expect(page.locator('#quickFormError')).toHaveText('اسم المستخدم أو كلمة السر غير صحيحة');
  expect(asked).toEqual([{ p_username: 'bashar', p_password: 'secret-1' }]);
  expect(calls.some(c => c.name === 'lookup_email_by_username')).toBe(false);
});

test('every CDN script tag is version-pinned, and carries an integrity hash where the CDN allows it', () => {
  const root = path.resolve(__dirname, '..');
  const bad = [];
  for (const f of fs.readdirSync(root).filter(f => f.endsWith('.html'))) {
    for (const tag of fs.readFileSync(path.join(root, f), 'utf8').match(/<script[^>]*\ssrc="https:\/\/[^"]+"[^>]*>/g) || []) {
      const src = tag.match(/src="([^"]+)"/)[1];
      const pinned = !/supabase-js@2"|supabase-js@2\/|cdn\.tailwindcss\.com(\?|"|$)/.test(src + '"') && !/plugins=forms,/.test(src);
      // cdn.tailwindcss.com sends no CORS header, so it can't take an integrity hash: pinned only
      const needsHash = !/cdn\.tailwindcss\.com/.test(src);
      if ((needsHash && (!/integrity="sha384-/.test(tag) || !/crossorigin="anonymous"/.test(tag))) || !pinned) bad.push(f + ': ' + src);
    }
  }
  expect(bad).toEqual([]);
});

// UX audit 2026-10-24: daily-cashbox naming and the phone "net today" sign.
test('daily cash box: one name for the balance, and the net keeps its sign in front on the phone', async ({ page }) => {
  await install(page, { db: { stores: [{ id: STORE, name: 'محل', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    daily_cash_log: [{ id: 'd1', store_id: STORE, direction: 'out', amount: 500, currency: 'AED', operation_type: 'مصروف', created_at: new Date().toISOString() }] } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/daily-cashbox-ar.html');
  const net = page.locator('#balances-by-currency p[dir="ltr"]');
  await expect(net).toHaveText(/^\u200e?-500\.00$/);
  const html = await page.content();
  expect(html).not.toContain('المفروض');
  expect(html).toContain('الرصيد الحالي');
});

// Purchase photos live in a private folder: the print page shows them through signed links.
test('purchase invoice photos are shown through signed links', async ({ page }) => {
  const pub = 'https://puzkfwbmipldzgwofhjg.supabase.co/storage/v1/object/public/invoice-attachments/' + STORE + '/purchase-PINV-1-photo-1.jpg';
  await install(page, { db: { stores: [{ id: STORE, name: 'محل', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [{ id: 'inv1', store_id: STORE, invoice_number: 'PINV-1', type: 'buyTrader', status: 'paid', total_amount: 100, created_at: new Date().toISOString(), bulk_photos: [pub] }], invoice_items: [] } });
  const signed = [];
  await page.route(/storage\/v1\/object\/sign\/invoice-attachments/, r => { const b = JSON.parse(r.request().postData()); signed.push(...b.paths); r.fulfill({ json: b.paths.map(p => ({ path: p, signedURL: '/object/sign/invoice-attachments/' + p + '?token=t', error: null })) }); });
  await page.route(/storage\/v1\/object\/(public|sign)\/invoice-attachments\/.*\.jpg/, r => r.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg"/>' }));
  await page.goto('/invoice-print-ar.html?id=inv1');
  const img = page.locator('#bulk-photos-grid img');
  await expect(img).toHaveAttribute('src', /\/object\/sign\/invoice-attachments\/.+purchase-PINV-1-photo-1\.jpg\?token=t/);
  expect(signed).toEqual([STORE + '/purchase-PINV-1-photo-1.jpg']);
});
