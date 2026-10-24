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
