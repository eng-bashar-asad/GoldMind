// GoldMind — RFID on Chainway handhelds (C72...) inside the Android app.
// Talks to GMUhfPlugin.java. Everywhere else (browser, ordinary phones)
// GMUhf.available() resolves false and pages keep their normal behaviour.
window.GMUhf = (function () {
  var C = window.Capacitor;
  var P = C && C.isNativePlatform && C.isNativePlatform() && C.Plugins && C.Plugins.GMUhf;
  var avail = null, tagListener = null;
  function err(e) { return new Error((e && e.message) || String(e)); }
  return {
    available: function () {
      if (!P) return Promise.resolve(false);
      if (avail !== null) return Promise.resolve(avail);
      return P.available().then(function (r) { avail = !!(r && r.available); return avail; }, function () { avail = false; return false; });
    },
    // nearest single tag
    readOne: function (power) { return P.readOne({ power: power || 10 }).then(function (r) { return r.epc; }, function (e) { throw err(e); }); },
    // writes the EPC of the label held against the device (low power), verified by reading back
    writeEpc: function (epc, power) { return P.writeEpc({ epc: epc, power: power || 5 }).catch(function (e) { throw err(e); }); },
    // continuous reading: onTag(epc) for every read (duplicates included — callers de-duplicate)
    start: function (onTag, power) {
      if (tagListener) { tagListener.remove(); tagListener = null; }
      return Promise.resolve(P.addListener('tag', function (t) { if (t && t.epc) onTag(t.epc); }))
        .then(function (h) { tagListener = h; return P.start({ power: power || 0 }); })
        .catch(function (e) { throw err(e); });
    },
    stop: function () {
      if (tagListener) { tagListener.remove(); tagListener = null; }
      return P ? P.stop() : Promise.resolve();
    },
    // hardware trigger: cb(true) pressed, cb(false) released
    onTrigger: function (cb) { if (P) P.addListener('trigger', function (e) { cb(!!(e && e.down)); }); }
  };
})();
