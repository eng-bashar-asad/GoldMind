// Fingerprint / Face ID login for GoldMind.
//  - Android app: the phone's fingerprint/face unlocks a device key kept in
//    the phone's secure storage (plugin @capgo/capacitor-native-biometric).
//  - Website (iPhone Safari, laptops): passkeys (WebAuthn) via Face ID / Touch ID / Windows Hello.
// The server side is the biometric-auth edge function; a successful check
// returns a one-time token that becomes a normal Supabase session here.
// Needs supabase-config.js (goldmindClient) loaded first.
(function () {
  var WEBAUTHN_LIB = 'https://cdn.jsdelivr.net/npm/@simplewebauthn/browser@14.0.0/dist/bundle/index.umd.min.js';
  var ACCOUNTS_KEY = 'gm_bio_accounts';      // Android: [{ user_id, label }]
  var PASSKEY_KEY = 'gm_passkey_users';      // Website: [{ user_id, label }] (hint only)

  function store(key, val) {
    try {
      if (val === undefined) return JSON.parse(localStorage.getItem(key) || '[]') || [];
      localStorage.setItem(key, JSON.stringify(val));
    } catch (e) { return []; }
  }
  function isNative() {
    return !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform());
  }
  function plugin() {
    return isNative() && window.Capacitor.Plugins ? window.Capacitor.Plugins.NativeBiometric : null;
  }
  function listKey() { return isNative() ? ACCOUNTS_KEY : PASSKEY_KEY; }
  function deviceName() {
    if (isNative()) return 'تطبيق أندرويد';
    var ua = navigator.userAgent;
    var d = /iPhone/.test(ua) ? 'iPhone' : /iPad/.test(ua) ? 'iPad' : /Android/.test(ua) ? 'Android'
      : /Mac/.test(ua) ? 'Mac' : /Windows/.test(ua) ? 'Windows' : 'متصفح';
    return d + ' — ' + new Date().toLocaleDateString('en-GB');
  }
  function loadLib() {
    if (window.SimpleWebAuthnBrowser) return Promise.resolve(window.SimpleWebAuthnBrowser);
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = WEBAUTHN_LIB;
      s.onload = function () { resolve(window.SimpleWebAuthnBrowser); };
      s.onerror = function () { reject(new Error('تعذّر التحميل — تأكد من الإنترنت')); };
      document.head.appendChild(s);
    });
  }

  async function call(body) {
    var res = await goldmindClient.functions.invoke('biometric-auth', { body: body });
    if (!res.error) return res.data;
    var msg = 'صار خطأ، جرّب مرة تانية';
    var status = res.error.context && res.error.context.status;
    try {
      var j = await res.error.context.json();
      if (j && j.error) msg = j.error;
    } catch (e) {
      if (!navigator.onLine) msg = 'الدخول بالبصمة بدو إنترنت';
    }
    var err = new Error(msg);
    err.status = status;
    throw err;
  }

  function friendly(e) {
    var name = e && e.name;
    if (name === 'NotAllowedError' || name === 'AbortError') return new Error('انلغت العملية');
    if (name === 'InvalidStateError') return new Error('البصمة مفعّلة من قبل على هالجهاز');
    // Android plugin: 10 failed, 16 user cancel, 13/15 cancelled
    var code = e && (e.code || e.errorCode);
    if (code == 16 || code == 15 || code == 13 || code == 11) return new Error('انلغت العملية');
    if (code == 10) return new Error('ما تعرّف على البصمة، جرّب مرة تانية');
    if (code == 2 || code == 4) return new Error('انقفلت البصمة مؤقتاً بسبب محاولات كتيرة. ادخل بكلمة السر.');
    return e instanceof Error ? e : new Error(String(e));
  }

  async function currentUser() {
    var s = await goldmindClient.auth.getSession();
    return s && s.data && s.data.session ? s.data.session.user : null;
  }

  async function startSession(tok) {
    var r = await goldmindClient.auth.verifyOtp({ token_hash: tok.token_hash, type: tok.type || 'magiclink' });
    if (r.error || !r.data || !r.data.user) throw new Error('تعذّر فتح الجلسة، جرّب مرة تانية');
    try { localStorage.setItem('goldmind_last_activity', String(Date.now())); } catch (e) { /* ignore */ }
    return r.data.user;
  }

  // "بالبصمة" for Arabic names, "بـ Face ID" for Latin ones.
  function bi(label) { return /^[\u0600-\u06FF]/.test(label) ? 'ب' + label : 'بـ ' + label; }

  var GMBio = {
    isNative: isNative,
    bi: bi,

    // What this device can do: { ok, label } — label is what we call it on buttons.
    available: async function () {
      try {
        if (isNative()) {
          var p = plugin();
          if (!p) return { ok: false };
          var r = await p.isAvailable({ useFallback: false });
          var face = r.biometryType === 2 || r.biometryType === 4;
          return { ok: !!r.isAvailable, label: face ? 'بصمة الوجه' : 'البصمة' };
        }
        if (!window.PublicKeyCredential || !PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable) return { ok: false };
        var ok = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
        var apple = /iPhone|iPad|Mac/.test(navigator.userAgent);
        return { ok: ok, label: apple ? 'Face ID / البصمة' : 'البصمة' };
      } catch (e) { return { ok: false }; }
    },

    // Accounts that turned it on from this device (for the login screen).
    accounts: function () { return store(listKey()); },

    enabledFor: function (userId) {
      return GMBio.accounts().some(function (a) { return a.user_id === userId; });
    },

    // Turn it on for the signed-in user on this device.
    enable: async function () {
      var user = await currentUser();
      if (!user) throw new Error('سجّل الدخول أول');
      try {
        if (isNative()) {
          var p = plugin();
          await p.verifyIdentity({ reason: 'تفعيل الدخول بالبصمة', title: 'تفعيل الدخول بالبصمة', negativeButtonText: 'إلغاء', maxAttempts: 5 });
          var k = await call({ action: 'device-enroll', device_name: deviceName() });
          // ponytail: the plugin keeps this in Android Keystore-backed storage and we gate
          // reading it behind verifyIdentity(); a CryptoObject-bound key is the upgrade path.
          await p.setCredentials({ server: 'goldmind-' + k.user_id, username: k.key_id, password: k.secret });
          saveAccount(k.user_id, k.label, { key_id: k.key_id });
        } else {
          var lib = await loadLib();
          var o = await call({ action: 'passkey-register-options' });
          var resp = await lib.startRegistration({ optionsJSON: o.options });
          await call({ action: 'passkey-register-verify', challenge_id: o.challenge_id, response: resp, device_name: deviceName() });
          saveAccount(user.id, (user.email || '').indexOf('@staff.goldmind.app') > 0 ? '' : user.email, { cred_id: resp.id });
        }
      } catch (e) { throw friendly(e); }
    },

    // Log in. On Android pass the chosen account's user_id; on the website the
    // browser shows its own list of saved accounts.
    login: async function (userId) {
      try {
        if (isNative()) {
          var p = plugin();
          var acc = GMBio.accounts().filter(function (a) { return a.user_id === userId; })[0] || GMBio.accounts()[0];
          if (!acc) throw new Error('البصمة مش مفعّلة على هالجهاز');
          await p.verifyIdentity({ reason: 'الدخول إلى GoldMind', title: 'تسجيل الدخول', subtitle: acc.label || '', negativeButtonText: 'إلغاء', maxAttempts: 5 });
          var cred = await p.getCredentials({ server: 'goldmind-' + acc.user_id });
          var tok;
          try {
            tok = await call({ action: 'device-login', key_id: cred.username, secret: cred.password });
          } catch (e) {
            if (e.status === 401) await GMBio.forgetHere(acc.user_id);
            throw e;
          }
          return await startSession(tok);
        }
        var lib = await loadLib();
        var o = await call({ action: 'passkey-login-options' });
        var resp = await lib.startAuthentication({ optionsJSON: o.options });
        var t = await call({ action: 'passkey-login-verify', challenge_id: o.challenge_id, response: resp });
        var user = await startSession(t);
        saveAccount(user.id, null);
        return user;
      } catch (e) { throw friendly(e); }
    },

    // Remove it from this device only (the server entry is removed from the security page).
    forgetHere: async function (userId) {
      var acc = GMBio.accounts().filter(function (a) { return a.user_id === userId; })[0] || {};
      store(listKey(), GMBio.accounts().filter(function (a) { return a.user_id !== userId; }));
      // Also drop this device's server entry when signed in (RLS: own rows only).
      try {
        if (acc.key_id) await goldmindClient.from('auth_device_keys').delete().eq('id', acc.key_id);
        if (acc.cred_id) await goldmindClient.from('auth_passkeys').delete().eq('id', acc.cred_id);
      } catch (e) { /* offline: the security page list can still remove it */ }
      if (isNative()) {
        try { await plugin().deleteCredentials({ server: 'goldmind-' + userId }); } catch (e) { /* already gone */ }
      }
    },

    // Offer to turn it on (dashboard), once per user per device.
    maybePrompt: async function () {
      var user = await currentUser();
      if (!user || GMBio.enabledFor(user.id)) return;
      var key = 'gm_bio_prompted_' + user.id;
      try { if (localStorage.getItem(key)) return; } catch (e) { return; }
      var av = await GMBio.available();
      if (!av.ok) return;
      showPrompt(av.label, function () { try { localStorage.setItem(key, '1'); } catch (e) { /* ignore */ } });
    },
  };

  function saveAccount(userId, label, extra) {
    var list = GMBio.accounts().filter(function (a) { return a.user_id !== userId; });
    var old = GMBio.accounts().filter(function (a) { return a.user_id === userId; })[0] || {};
    list.unshift(Object.assign({}, old, extra || {}, { user_id: userId, label: label || old.label || '' }));
    store(listKey(), list.slice(0, 6));
  }

  function showPrompt(label, done) {
    if (document.getElementById('gm-bio-prompt')) return;
    var box = document.createElement('div');
    box.id = 'gm-bio-prompt';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-label', 'تفعيل الدخول بالبصمة');
    box.dir = 'rtl';
    box.style.cssText = 'position:fixed;left:12px;right:12px;bottom:calc(16px + env(safe-area-inset-bottom));z-index:9999;max-width:420px;margin:0 auto;background:#0B1A20;color:#fff;border:1px solid rgba(212,175,55,.45);border-radius:16px;padding:16px;box-shadow:0 18px 40px -12px rgba(0,0,0,.55);font-size:14px';
    box.innerHTML =
      '<div style="display:flex;gap:10px;align-items:flex-start">' +
      '<span class="material-symbols-outlined" aria-hidden="true" style="color:#D4AF37;font-size:28px">fingerprint</span>' +
      '<div style="flex:1"><div style="font-weight:700;margin-bottom:4px">ادخل المرة الجاية ' + bi(label) + '</div>' +
      '<div style="opacity:.75;font-size:12.5px;line-height:1.6">بدون ما تكتب كلمة السر. البصمة بتضل على جهازك وما بتنبعت لأي مكان.</div></div></div>' +
      '<div style="display:flex;gap:8px;margin-top:12px">' +
      '<button type="button" id="gm-bio-yes" style="flex:1;min-height:44px;border-radius:10px;border:0;background:#D4AF37;color:#2E2113;font-weight:700">تفعيل</button>' +
      '<button type="button" id="gm-bio-no" style="flex:1;min-height:44px;border-radius:10px;border:1px solid rgba(255,255,255,.25);background:transparent;color:#fff">مش هلق</button></div>' +
      '<p id="gm-bio-msg" role="status" style="margin:8px 0 0;font-size:12px;min-height:1em"></p>';
    document.body.appendChild(box);
    var msg = box.querySelector('#gm-bio-msg');
    box.querySelector('#gm-bio-no').onclick = function () { done(); box.remove(); };
    box.querySelector('#gm-bio-yes').onclick = async function () {
      var btn = this;
      btn.disabled = true;
      msg.textContent = '';
      try {
        await GMBio.enable();
        done();
        msg.style.color = '#9BE3B0';
        msg.textContent = 'تم التفعيل ✓';
        setTimeout(function () { box.remove(); }, 1500);
      } catch (e) {
        btn.disabled = false;
        msg.style.color = '#FFB4A8';
        msg.textContent = e.message;
        if (/موقوف/.test(e.message)) { done(); setTimeout(function () { box.remove(); }, 3000); }
      }
    };
  }

  window.GMBio = GMBio;
})();
