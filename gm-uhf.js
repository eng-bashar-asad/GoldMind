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

// ── Computer (Chrome / Edge): the Zebra RFD40 paired over Bluetooth shows up as a COM port, and the
// sled speaks ZETI (Zebra's text commands) over it. Web Serial opens that port, so the same GMUhf API
// works on the laptop. The first time the user picks the port (GMUhf.connectSerial, needs a click);
// after that the browser remembers it and every page reconnects by itself.
// ponytail: ZETI's write syntax isn't published online, so writeEpc tries the known spellings in turn
// and keeps the one the sled accepts (localStorage gm_zeti_write); every write is verified by reading
// the tag back. GMUhf.log() holds the raw exchange for diagnosing a new firmware.
(function () {
  if (window.GMUhf.native || !('serial' in navigator)) return;
  var base = window.GMUhf, SPP = '00001101-0000-1000-8000-00805f9b34fb';
  var port = null, writer = null, buf = '', lines = [], waiters = [], tagCbs = [], logBuf = [], opening = null, running = false;
  var WKEY = 'gm_zeti_write';
  var WRITES = [
    'write .memorybank epc .offset 2 .data {D}',
    'wr .mb epc .os 2 .da {D}',
    'write -memorybank epc -offset 2 -data {D}',
    'wr -mb epc -os 2 -d {D}',
    'write -mb epc -os 2 -data {D}',
    'writetag .memorybank epc .offset 2 .data {D}'
  ];
  function log(s) { logBuf.push(new Date().toISOString().slice(11, 19) + ' ' + s); if (logBuf.length > 400) logBuf.shift(); }
  function epcIn(line) {
    // a tag report carries the EPC as a long hex token; skip echoes and status lines
    if (/^(command|ok|error|notification|event)/i.test(line)) return null;
    var t = line.split(/[\s,;:=]+/).filter(function (x) { return /^[0-9A-Fa-f]{16,64}$/.test(x) && x.length % 4 === 0; });
    return t.length ? t[0].toUpperCase() : null;
  }
  function onLine(line) {
    line = line.trim(); if (!line) return;
    log('< ' + line);
    var e = epcIn(line); if (e) tagCbs.slice().forEach(function (cb) { cb(e); });
    lines.push(line);
    waiters.slice().forEach(function (w) { w(line); });
  }
  async function pump(p) {
    var dec = new TextDecoder();
    while (p === port && p.readable) {
      var r = p.readable.getReader();
      try {
        for (;;) {
          var x = await r.read(); if (x.done) break;
          buf += dec.decode(x.value, { stream: true });
          var parts = buf.split(/\r?\n|\r/); buf = parts.pop();
          parts.forEach(onLine);
        }
      } catch (e) { log('! read: ' + e.message); break; } finally { try { r.releaseLock(); } catch (e) {} }
    }
  }
  function send(cmd) { log('> ' + cmd); return writer.write(new TextEncoder().encode(cmd + '\r\n')); }
  // sends a command and resolves with its reply lines once OK / ERROR arrives (or the time runs out)
  function cmd(c, ms) {
    return new Promise(function (res) {
      var got = [], done = false;
      function fin() { if (done) return; done = true; waiters = waiters.filter(function (w) { return w !== take; }); res(got); }
      function take(l) { got.push(l); if (/^(ok|error)\b/i.test(l) || /\b(invalid|unknown|not supported)\b/i.test(l)) setTimeout(fin, 60); }
      waiters.push(take); setTimeout(fin, ms || 2500);
      send(c).catch(function (e) { log('! write: ' + e.message); fin(); });
    });
  }
  async function open(p) {
    try { await p.open({ baudRate: 115200 }); }
    catch (e) { if (!/already open/i.test(e.message)) { log('! open: ' + e.message); throw new Error(/busy|access|denied|failed to open/i.test(e.message) ? 'منفذ الزيبرا مشغول — أغلق برنامج 123RFID Desktop وحاول مرة أخرى.' : 'تعذّر فتح منفذ الزيبرا: ' + e.message); } }
    port = p; writer = p.writable.getWriter(); pump(p);
    await cmd('cn', 2500); // "connect": the sled answers ZETI after this
    var v = await cmd('gv', 2000);
    log('connected ' + JSON.stringify(p.getInfo ? p.getInfo() : {}) + ' ' + v.join(' | '));
    return true;
  }
  function ensure() {
    if (port) return Promise.resolve(true);
    if (!opening) opening = navigator.serial.getPorts().then(function (ps) { return ps.length ? open(ps[0]) : false; })
      .catch(function (e) { log('! ' + e.message); return false; }).then(function (ok) { opening = null; return ok; });
    return opening;
  }
  // tags seen during ms (one short inventory)
  async function sweep(ms) {
    var seen = {};
    function cb(e) { seen[e] = (seen[e] || 0) + 1; }
    tagCbs.push(cb);
    await send('in'); await new Promise(function (r) { setTimeout(r, ms || 900); }); await cmd('a', 1200);
    tagCbs = tagCbs.filter(function (x) { return x !== cb; });
    return seen;
  }
  function only(seen) {
    var k = Object.keys(seen);
    if (!k.length) throw new Error('لم تُقرأ أي ملصقة — قرّب الملصقة من رأس جهاز الزيبرا.');
    if (k.length > 1) throw new Error('قرأ الجهاز ' + k.length + ' ملصقات — أبعد باقي القطع واترك ملصقة واحدة أمامه.');
    return k[0];
  }
  window.GMUhf = Object.assign({}, base, {
    serial: true,
    log: function () { return logBuf.join('\n'); },
    send: function (c) { return ensure().then(function (ok) { if (!ok) throw new Error('الجهاز غير موصول'); return cmd(c, 3000); }); },
    connectSerial: async function () {
      var p;
      try { p = await navigator.serial.requestPort({ allowedBluetoothServiceClassIds: [SPP] }); }
      catch (e) { if (e.name === 'NotFoundError') return false; p = await navigator.serial.requestPort(); }
      if (port && port !== p) await window.GMUhf.disconnect();
      return open(p);
    },
    available: function () { return ensure(); },
    status: function () {
      return ensure().then(function (ok) {
        var i = ok && port.getInfo ? port.getInfo() : {};
        return { available: !!ok, kind: 'zebra', name: ok ? 'Zebra RFD40 (كمبيوتر)' + (i.bluetoothServiceClassId ? ' · بلوتوث' : '') : '' };
      });
    },
    disconnect: async function () {
      var p = port; port = null; running = false;
      try { if (writer) { writer.releaseLock(); writer = null; } if (p) await p.close(); } catch (e) { log('! close: ' + e.message); }
    },
    readOne: async function () { if (!(await ensure())) throw new Error('جهاز الزيبرا غير موصول'); return only(await sweep(900)); },
    writeEpc: async function (epc) {
      if (!(await ensure())) throw new Error('جهاز الزيبرا غير موصول');
      epc = String(epc).toUpperCase();
      only(await sweep(900)); // exactly one label in front of the sled, or we stop before writing
      var saved = null; try { saved = localStorage.getItem(WKEY); } catch (e) {}
      var tries = saved ? [saved].concat(WRITES.filter(function (w) { return w !== saved; })) : WRITES;
      for (var i = 0; i < tries.length; i++) {
        var r = await cmd(tries[i].replace('{D}', epc), 4000), txt = r.join(' ');
        if (/\berror\b|invalid|unknown|not supported|usage/i.test(txt)) continue;
        var after = await sweep(900);
        if (after[epc]) { try { localStorage.setItem(WKEY, tries[i]); } catch (e) {} return; }
        if (/\bok\b/i.test(txt)) throw new Error('قبل الجهاز الأمر لكن الملصقة لم تتغيّر — قرّبها أكثر وحاول مرة أخرى.');
      }
      throw new Error('تعذّر العثور على أمر الكتابة المناسب لهذا الجهاز. افتح «سجل الجهاز» في صفحة الشرائح وأرسله للدعم الفني.');
    },
    start: async function (onTag) {
      if (!(await ensure())) throw new Error('جهاز الزيبرا غير موصول');
      tagCbs = [onTag]; running = true; await send('in');
    },
    stop: async function () { tagCbs = []; if (port && running) { running = false; await cmd('a', 1200); } },
    onTrigger: function () { /* the trigger on the sled already starts reading by itself in ZETI mode */ }
  });
  window.addEventListener('pagehide', function () { if (port) window.GMUhf.disconnect(); });
})();
