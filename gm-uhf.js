// GoldMind — RFID inside the Android app: Chainway / Urovo handhelds and the Zebra RFD40 Bluetooth
// sled (GMUhfPlugin.java). Everywhere else (browser, ordinary phones) GMUhf.available() resolves
// false and pages keep their normal behaviour.
// Per-device settings (devices-setup-ar.html, kept on this phone): write power, count power and how
// the trigger starts/stops a count. Calls without an explicit power use them.
window.GMUhf = (function () {
  var C = window.Capacitor;
  var P = C && C.isNativePlatform && C.isNativePlatform() && C.Plugins && C.Plugins.GMUhf;
  var avail = null, tagListener = null, toggled = false;
  var KEY = 'gm_rfid_settings', DEF = { writePower: 5, countPower: 0, trigger: 'hold' };
  function err(e) { return new Error((e && e.message) || String(e)); }
  function settings() {
    var s = {};
    try { s = JSON.parse(localStorage.getItem(KEY) || '{}') || {}; } catch (e) { s = {}; }
    return { writePower: Number(s.writePower) || DEF.writePower, countPower: s.countPower == null ? DEF.countPower : Number(s.countPower) || 0, trigger: s.trigger === 'toggle' ? 'toggle' : 'hold' };
  }
  return {
    settings: settings,
    saveSettings: function (s) { try { localStorage.setItem(KEY, JSON.stringify(Object.assign(settings(), s || {}))); } catch (e) { /* private mode */ } return settings(); },
    native: !!P,
    available: function () {
      if (!P) return Promise.resolve(false);
      if (avail === true) return Promise.resolve(true);
      return P.available().then(function (r) { avail = !!(r && r.available); return avail; }, function () { avail = false; return false; });
    },
    // {available, kind: chainway|urovo|zebra|none, name} — connects the sled if it is paired and on
    status: function () {
      if (!P || !P.status) return Promise.resolve({ available: false, kind: 'none', name: '' });
      return P.status().then(function (r) { avail = !!(r && r.available); return r || { available: false, kind: 'none', name: '' }; }, function () { return { available: false, kind: 'none', name: '' }; });
    },
    disconnect: function () { avail = null; return P && P.disconnect ? P.disconnect().catch(function () {}) : Promise.resolve(); },
    // nearest single tag
    readOne: function (power) { return P.readOne({ power: power || 10 }).then(function (r) { return r.epc; }, function (e) { throw err(e); }); },
    // writes the EPC of the label held against the device (low power), verified by reading back
    writeEpc: function (epc, power) { return P.writeEpc({ epc: epc, power: power || settings().writePower }).catch(function (e) { throw err(e); }); },
    // continuous reading: onTag(epc) for every read (duplicates included — callers de-duplicate)
    start: function (onTag, power) {
      if (tagListener) { tagListener.remove(); tagListener = null; }
      return Promise.resolve(P.addListener('tag', function (t) { if (t && t.epc) onTag(t.epc); }))
        .then(function (h) { tagListener = h; return P.start({ power: power != null ? power : settings().countPower }); })
        .catch(function (e) { throw err(e); });
    },
    stop: function () {
      toggled = false;
      if (tagListener) { tagListener.remove(); tagListener = null; }
      return P ? P.stop() : Promise.resolve();
    },
    // hardware trigger: cb(true) = start, cb(false) = stop.
    // "hold": reads while pressed. "toggle": one press starts, the next press stops.
    onTrigger: function (cb) {
      if (!P) return;
      P.addListener('trigger', function (e) {
        var down = !!(e && e.down);
        if (settings().trigger === 'toggle') { if (!down) return; toggled = !toggled; cb(toggled); }
        else cb(down);
      });
    }
  };
})();
