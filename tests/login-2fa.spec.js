// Two-step login: a password session must enter the emailed 8-digit code; fingerprint
// (otp) sessions and username-only accounts go straight in.
const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');
const PW = { amr: [{ method: 'password', timestamp: 1 }], session_id: 'sess-1', email: 'roba@example.com' };

test('password session is sent to the code page and comes back after the right code', async ({ page }) => {
  let ok = false;
  await install(page, { generic: true, claims: PW, rpc: { gm_session_ok: () => ({ body: ok }) } });
  const fn = [];
  await page.route(/functions\/v1\/login-2fa/, async r => {
    const b = JSON.parse(r.request().postData() || '{}'); fn.push(b);
    if (b.action === 'send') return r.fulfill({ json: { ok: true, sent: true, to: 'ro***@example.com', ttl: 60 } });
    if (b.code === '12345678') { ok = true; return r.fulfill({ json: { ok: true, verified: true } }); }
    return r.fulfill({ status: 400, json: { error: 'الرمز غير صحيح', left: 4 } });
  });
  await page.goto('/accounting-check-ar.html');
  await expect(page).toHaveURL(/login-2fa-ar\.html\?next=accounting-check-ar\.html/);
  await expect(page.locator('#info')).toContainText('ro***@example.com');
  await expect(page.locator('#timer')).toContainText('ثانية');
  await page.fill('#code', '11112222');
  await expect(page.locator('#err')).toContainText('الرمز غير صحيح');
  await page.fill('#code', '12345678');
  await expect(page).toHaveURL(/accounting-check-ar\.html$/);
  expect(fn.some(b => b.action === 'send')).toBe(true);
  expect(fn.filter(b => b.action === 'verify').map(b => b.code)).toEqual(['11112222', '12345678']);
});

test('fingerprint (otp) session and username-only accounts are not asked', async ({ page }) => {
  await install(page, { generic: true, claims: { amr: [{ method: 'otp' }], session_id: 's2', email: 'a@b.com' }, rpc: { gm_session_ok: () => ({ body: false }), accounting_health_check: () => ({ body: [] }) } });
  await page.goto('/accounting-check-ar.html');
  await expect(page.locator('#summary')).toContainText('سليمة');
  const p2 = await page.context().newPage();
  await install(p2, { generic: true, claims: { amr: [{ method: 'password' }], session_id: 's3', email: 'saqer.9c2ce2f0@staff.goldmind.app' }, rpc: { gm_session_ok: () => ({ body: false }), accounting_health_check: () => ({ body: [] }) } });
  await p2.goto('/accounting-check-ar.html');
  await expect(p2.locator('#summary')).toContainText('سليمة');
});

test('the code page never sends you to an outside address', async ({ page }) => {
  await install(page, { generic: true, claims: PW, rpc: { gm_session_ok: () => ({ body: true }) } });
  await page.goto('/login-2fa-ar.html?next=' + encodeURIComponent('https://evil.example/x.html'));
  await expect(page).toHaveURL(/\/index-ar\.html$/);
});

test('password login on the login page goes to the code page, then finishes the sign-in', async ({ page }) => {
  await page.addInitScript(() => { try { localStorage.removeItem('sb-puzkfwbmipldzgwofhjg-auth-token'); } catch (e) {} });
  await install(page, { generic: true, claims: PW, rpc: { gm_session_ok: () => ({ body: false }) } });
  await page.goto('/login-entry-ar.html?mode=quick');
  await page.fill('#quickIdentifier', 'roba@example.com');
  await page.fill('#quickPassword', 'secret123');
  await page.click('#quickSubmitBtn');
  await expect(page).toHaveURL(/login-2fa-ar\.html\?next=login-entry-ar\.html%3Fresume%3D1/);
});
