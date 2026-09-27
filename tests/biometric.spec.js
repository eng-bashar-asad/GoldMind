// Fingerprint / Face ID login, end to end, with the real server logic
// (supabase/functions/biometric-auth/core.js) behind a fake Supabase.
//  - Website: a virtual fingerprint device in Chromium (real WebAuthn crypto).
//  - Android app: a stand-in for the native fingerprint plugin.
const { test, expect } = require('@playwright/test');
const path = require('path');
const fs = require('fs');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const WEBAUTHN_UMD = fs.readFileSync(path.join(__dirname, 'node_modules/@simplewebauthn/browser/dist/bundle/index.umd.min.js'), 'utf8');

async function loadCore() {
  const core = await import(path.join(__dirname, '../supabase/functions/biometric-auth/core.js'));
  const swa = await import('@simplewebauthn/server');
  return { core, swa };
}

// In-memory version of the tables + rules index.ts uses.
function memoryDb(allow = true) {
  const t = { passkeys: [], keys: [], challenges: [] };
  let n = 0;
  return {
    t,
    async biometricAllowed() { return allow; },
    async userLabel() { return 'bashar'; },
    async listPasskeys(u) { return t.passkeys.filter((p) => p.user_id === u); },
    async createChallenge(row) { const id = 'ch' + (++n); t.challenges.push({ ...row, id, expires_at: Date.now() + 300000 }); return id; },
    async takeChallenge(id, kind) {
      const i = t.challenges.findIndex((c) => c.id === id && c.kind === kind);
      if (i < 0) return null;
      const [c] = t.challenges.splice(i, 1);
      return c.expires_at > Date.now() ? c : null;
    },
    async insertPasskey(row) { t.passkeys.push({ ...row }); },
    async getPasskey(id) { return t.passkeys.find((p) => p.id === id) || null; },
    async touchPasskey(id, counter) { const p = t.passkeys.find((x) => x.id === id); p.counter = counter; p.last_used_at = Date.now(); },
    async insertDeviceKey(row) { const id = '00000000-0000-4000-8000-00000000000' + (++n % 10); t.keys.push({ ...row, id }); return id; },
    async getDeviceKey(id) { return t.keys.find((k) => k.id === id) || null; },
    async touchDeviceKey() {},
  };
}

async function setup(page, { allow = true } = {}) {
  const { core, swa } = await loadCore();
  const db = memoryDb(allow);
  const minted = [];
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار', whatsapp_phone: null }],
    user_profiles: [{ id: USER, username: 'bashar', privacy_accepted_at: '2026-01-01' }],
    auth_passkeys: [], auth_device_keys: [],
  } });
  await page.route(/@simplewebauthn\/browser/, (r) => r.fulfill({ contentType: 'text/javascript', body: WEBAUTHN_UMD }));
  await page.route(/\/functions\/v1\/biometric-auth/, async (r) => {
    const body = JSON.parse(r.request().postData() || '{}');
    const ctx = {
      swa, db,
      cfg: { rpID: 'localhost', rpName: 'GoldMind', origins: ['http://localhost:4173'] },
      userId: USER,
      async mint(u) { minted.push(u); return { token_hash: 'th-' + minted.length, type: 'magiclink' }; },
    };
    const out = await core.handle(ctx, body);
    return r.fulfill({ status: out.status, contentType: 'application/json', body: JSON.stringify(out.body) });
  });
  return { db, minted };
}

async function virtualFingerprint(page) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('WebAuthn.enable');
  await cdp.send('WebAuthn.addVirtualAuthenticator', { options: {
    protocol: 'ctap2', transport: 'internal', hasResidentKey: true, hasUserVerification: true, isUserVerified: true, automaticPresenceSimulation: true,
  } });
}

test('website: turn on Face ID/fingerprint, then log in with it', async ({ page }) => {
  const { db, minted } = await setup(page);
  await virtualFingerprint(page);

  await page.goto('/account-security-ar.html');
  await expect(page.locator('#bioToggleBtn')).toContainText('تفعيل');
  await page.click('#bioToggleBtn');
  await expect(page.locator('#bioSuccess')).toContainText('تم التفعيل');
  expect(db.t.passkeys).toHaveLength(1);
  expect(db.t.passkeys[0].user_id).toBe(USER);

  await page.goto('/login-entry-ar.html');
  const btn = page.locator('#step-start [data-bio-accounts] button');
  await expect(btn).toContainText('دخول ب');
  await btn.click();
  await page.waitForURL(/index-ar\.html/);
  expect(minted).toEqual([USER]);
  expect(db.t.passkeys[0].last_used_at).toBeTruthy();
});

test('website: a passkey the server no longer knows is refused', async ({ page }) => {
  const { db, minted } = await setup(page);
  await virtualFingerprint(page);
  await page.goto('/account-security-ar.html');
  await page.click('#bioToggleBtn');
  await expect(page.locator('#bioSuccess')).toContainText('تم التفعيل');
  db.t.passkeys.length = 0; // removed from the security page on another device
  await page.goto('/login-entry-ar.html');
  await page.locator('#step-start [data-bio-accounts] button').click();
  await expect(page.locator('#step-start [data-bio-error]')).toContainText('غير مرتبطة');
  expect(minted).toEqual([]);
});

// Android app: stand-in for window.Capacitor + the NativeBiometric plugin.
async function fakeAndroid(page) {
  await page.addInitScript(() => {
    const vault = JSON.parse(sessionStorage.getItem('__vault') || '{}');
    const save = () => sessionStorage.setItem('__vault', JSON.stringify(vault));
    window.__bioChecks = 0;
    window.Capacitor = {
      isNativePlatform: () => true,
      getPlatform: () => 'android',
      Plugins: { NativeBiometric: {
        isAvailable: async () => ({ isAvailable: true, biometryType: 3 }),
        verifyIdentity: async () => { window.__bioChecks++; },
        setCredentials: async ({ server, username, password }) => { vault[server] = { username, password }; save(); },
        getCredentials: async ({ server }) => { if (!vault[server]) throw new Error('none'); return vault[server]; },
        deleteCredentials: async ({ server }) => { delete vault[server]; save(); },
      } },
    };
  });
}

test('android app: turn on fingerprint, then log in with it', async ({ page }) => {
  const { db, minted } = await setup(page);
  await fakeAndroid(page);
  await page.goto('/account-security-ar.html');
  await page.click('#bioToggleBtn');
  await expect(page.locator('#bioSuccess')).toContainText('تم التفعيل');
  expect(db.t.keys).toHaveLength(1);
  expect(db.t.keys[0].secret_hash).toMatch(/^[0-9a-f]{64}$/);

  await page.goto('/login-entry-ar.html');
  const btn = page.locator('#step-start [data-bio-accounts] button');
  await expect(btn).toContainText('دخول بالبصمة');
  await btn.click();
  await page.waitForURL(/index-ar\.html/);
  expect(minted).toEqual([USER]);
});

test('android app: removed device key is refused and forgotten on the phone', async ({ page }) => {
  const { db, minted } = await setup(page);
  await fakeAndroid(page);
  await page.goto('/account-security-ar.html');
  await page.click('#bioToggleBtn');
  await expect(page.locator('#bioSuccess')).toContainText('تم التفعيل');
  db.t.keys.length = 0;
  await page.goto('/login-entry-ar.html');
  await page.locator('#step-start [data-bio-accounts] button').click();
  await expect(page.locator('#step-start [data-bio-error]')).toContainText('أُزيلت');
  expect(minted).toEqual([]);
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('gm_bio_accounts') || '[]').length)).toBe(0);
});

test('company switched it off: turning it on is refused with a clear message', async ({ page }) => {
  await setup(page, { allow: false });
  await fakeAndroid(page);
  await page.goto('/account-security-ar.html');
  await page.click('#bioToggleBtn');
  await expect(page.locator('#bioError')).toContainText('موقوف');
});

test('server rejects a wrong device secret', async () => {
  const { core, swa } = await loadCore();
  const db = memoryDb();
  const ctx = { swa, db, cfg: { rpID: 'localhost', rpName: 'x', origins: [] }, userId: USER, mint: async () => ({ token_hash: 'x' }) };
  const enrolled = (await core.handle(ctx, { action: 'device-enroll', device_name: '<b>phone</b>' })).body;
  expect(db.t.keys[0].device_name).toBe('bphone/b');
  const anon = { ...ctx, userId: null };
  expect((await core.handle(anon, { action: 'device-login', key_id: enrolled.key_id, secret: enrolled.secret + 'x' })).status).toBe(401);
  expect((await core.handle(anon, { action: 'device-login', key_id: enrolled.key_id, secret: enrolled.secret })).status).toBe(200);
  expect((await core.handle(anon, { action: 'device-enroll' })).status).toBe(401);
  expect((await core.handle(anon, { action: 'passkey-register-options' })).status).toBe(401);
});

test('android app, not turned on yet: login screen explains how to turn it on', async ({ page }) => {
  await setup(page);
  await fakeAndroid(page);
  await page.goto('/login-entry-ar.html');
  await expect(page.locator('#step-start')).toContainText('سجّل الدخول مرة واحدة بكلمة السر');
  await expect(page.locator('#step-start [data-bio-accounts] button')).toHaveCount(0);
});
