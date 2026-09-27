// Core of the biometric-auth edge function, kept free of Deno/Supabase
// specifics so the exact same code runs in the local tests (tests/biometric.spec.js).
//
// Two ways to log in without typing a password:
//  - Passkeys (WebAuthn): the website on iPhone (Face ID), Mac/Windows laptops.
//  - Device keys: the Android app keeps a random secret in the phone's secure
//    storage and hands it over only after the phone's fingerprint/face check.
// Either way, success ends with a one-time sign-in token for that user.
//
// ctx = {
//   swa,                 // @simplewebauthn/server
//   db,                  // storage adapter (see index.ts / the test for the methods)
//   mint(userId),        // -> { token_hash, type } one-time sign-in token
//   cfg: { rpID, rpName, origins: string[] },
//   userId,              // caller's user id when a valid session was sent, else null
// }

const b64u = {
  encode(bytes) {
    let s = '';
    for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  },
  decode(str) {
    const s = atob(str.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((str.length + 3) % 4));
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  },
};

async function sha256Hex(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function cleanName(name) {
  return String(name || '').replace(/[<>]/g, '').trim().slice(0, 60) || null;
}

class Fail extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const NEED_LOGIN = () => new Fail(401, 'الجلسة غير صالحة، سجّل الدخول من جديد');
const NOT_ALLOWED = () => new Fail(403, 'الدخول بالبصمة موقوف لحسابك من إعدادات الشركة. ادخل بكلمة السر.');

async function finishLogin(ctx, userId) {
  if (!(await ctx.db.biometricAllowed(userId))) throw NOT_ALLOWED();
  return ctx.mint(userId);
}

const actions = {
  // ---- Passkeys (website) ----
  async 'passkey-register-options'(ctx, body) {
    if (!ctx.userId) throw NEED_LOGIN();
    if (!(await ctx.db.biometricAllowed(ctx.userId))) throw NOT_ALLOWED();
    const label = await ctx.db.userLabel(ctx.userId);
    const existing = await ctx.db.listPasskeys(ctx.userId);
    const options = await ctx.swa.generateRegistrationOptions({
      rpName: ctx.cfg.rpName,
      rpID: ctx.cfg.rpID,
      userName: label,
      userDisplayName: label,
      userID: new TextEncoder().encode(ctx.userId),
      attestationType: 'none',
      excludeCredentials: existing.map((p) => ({ id: p.id, transports: p.transports || undefined })),
      authenticatorSelection: { residentKey: 'required', userVerification: 'required' },
    });
    const challengeId = await ctx.db.createChallenge({ challenge: options.challenge, user_id: ctx.userId, kind: 'register' });
    return { options, challenge_id: challengeId };
  },

  async 'passkey-register-verify'(ctx, body) {
    if (!ctx.userId) throw NEED_LOGIN();
    const ch = await ctx.db.takeChallenge(body.challenge_id, 'register');
    if (!ch || ch.user_id !== ctx.userId) throw new Fail(400, 'انتهت مهلة التفعيل، جرّب مرة تانية');
    let result;
    try {
      result = await ctx.swa.verifyRegistrationResponse({
        response: body.response,
        expectedChallenge: ch.challenge,
        expectedOrigin: ctx.cfg.origins,
        expectedRPID: ctx.cfg.rpID,
        requireUserVerification: true,
      });
    } catch (e) {
      throw new Fail(400, 'تعذّر التحقق من البصمة: ' + e.message);
    }
    if (!result.verified) throw new Fail(400, 'تعذّر التحقق من البصمة');
    const cred = result.registrationInfo.credential;
    await ctx.db.insertPasskey({
      id: cred.id,
      user_id: ctx.userId,
      public_key: b64u.encode(cred.publicKey),
      counter: cred.counter || 0,
      transports: cred.transports || null,
      device_name: cleanName(body.device_name),
    });
    return { ok: true };
  },

  async 'passkey-login-options'(ctx) {
    const options = await ctx.swa.generateAuthenticationOptions({
      rpID: ctx.cfg.rpID,
      userVerification: 'required',
      allowCredentials: [], // discoverable: the phone/laptop shows its saved accounts
    });
    const challengeId = await ctx.db.createChallenge({ challenge: options.challenge, user_id: null, kind: 'login' });
    return { options, challenge_id: challengeId };
  },

  async 'passkey-login-verify'(ctx, body) {
    const ch = await ctx.db.takeChallenge(body.challenge_id, 'login');
    if (!ch) throw new Fail(400, 'انتهت المهلة، جرّب مرة تانية');
    const credId = body.response && body.response.id;
    const pk = credId ? await ctx.db.getPasskey(credId) : null;
    if (!pk) throw new Fail(400, 'هالبصمة مش مربوطة بأي حساب. ادخل بكلمة السر وفعّلها من جديد.');
    let result;
    try {
      result = await ctx.swa.verifyAuthenticationResponse({
        response: body.response,
        expectedChallenge: ch.challenge,
        expectedOrigin: ctx.cfg.origins,
        expectedRPID: ctx.cfg.rpID,
        credential: { id: pk.id, publicKey: b64u.decode(pk.public_key), counter: Number(pk.counter) || 0, transports: pk.transports || undefined },
        requireUserVerification: true,
      });
    } catch (e) {
      throw new Fail(400, 'تعذّر التحقق من البصمة: ' + e.message);
    }
    if (!result.verified) throw new Fail(400, 'تعذّر التحقق من البصمة');
    await ctx.db.touchPasskey(pk.id, result.authenticationInfo.newCounter);
    return finishLogin(ctx, pk.user_id);
  },

  // ---- Device keys (Android app) ----
  async 'device-enroll'(ctx, body) {
    if (!ctx.userId) throw NEED_LOGIN();
    if (!(await ctx.db.biometricAllowed(ctx.userId))) throw NOT_ALLOWED();
    const secret = b64u.encode(crypto.getRandomValues(new Uint8Array(32)));
    const id = await ctx.db.insertDeviceKey({
      user_id: ctx.userId,
      secret_hash: await sha256Hex(secret),
      device_name: cleanName(body.device_name),
    });
    return { key_id: id, secret, user_id: ctx.userId, label: await ctx.db.userLabel(ctx.userId) };
  },

  async 'device-login'(ctx, body) {
    const key = body.key_id ? await ctx.db.getDeviceKey(String(body.key_id)) : null;
    if (!key || !safeEqual(key.secret_hash, await sha256Hex(String(body.secret || '')))) {
      throw new Fail(401, 'البصمة على هالجهاز مش مفعّلة أو انشالت. ادخل بكلمة السر وفعّلها من جديد.');
    }
    await ctx.db.touchDeviceKey(key.id);
    return finishLogin(ctx, key.user_id);
  },
};

export async function handle(ctx, body) {
  const fn = actions[body && body.action];
  if (!fn) return { status: 400, body: { error: 'unknown action' } };
  try {
    return { status: 200, body: await fn(ctx, body) };
  } catch (e) {
    if (e instanceof Fail) return { status: e.status, body: { error: e.message } };
    return { status: 500, body: { error: String(e && e.message || e) } };
  }
}

export const _test = { b64u, sha256Hex, safeEqual };
