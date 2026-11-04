// Home «أدوات سريعة»: three closed glass buttons; a tap opens its box under them, a second tap closes it.
//  • العملات  — today's rates of the main currencies against the branch currency + a converter.
//               Rates: open.er-api.com once a day (kept in fx_rates_daily). Syrian pound: the branch's own
//               market rate (stores.secondary_currency_rate, set on «سعر الذهب») when it has one.
//  • الحاسبة  — weight × karat price + making = piece price (karat prices from «سعر الذهب»).
//  • المواسم  — the coming occasions of the branch's country with a day countdown.
(function () {
  var MAIN = ['USD', 'EUR', 'AED', 'SAR', 'GBP', 'TRY', 'KWD', 'QAR', 'JOD', 'EGP', 'SYP'];
  var CUR_AR = { USD: 'دولار أمريكي', EUR: 'يورو', AED: 'درهم إماراتي', SAR: 'ريال سعودي', GBP: 'جنيه إسترليني', TRY: 'ليرة تركية', KWD: 'دينار كويتي', QAR: 'ريال قطري', JOD: 'دينار أردني', EGP: 'جنيه مصري', SYP: 'ليرة سورية' };
  var TOOLS = [
    { k: 'fx', t: 'العملات', s: 'أسعار اليوم والتحويل', ic: 'currency_exchange', c1: '#2E8B7A', c2: '#8FD3C3', tint: 'rgba(143,211,195,.30)' },
    { k: 'calc', t: 'الحاسبة', s: 'سعر القطعة بسرعة', ic: 'calculate', c1: '#6D5BD0', c2: '#C2B8F2', tint: 'rgba(194,184,242,.30)' },
    { k: 'seasons', t: 'المواسم', s: 'المناسبات القادمة', ic: 'celebration', c1: '#C0567A', c2: '#F2B8C9', tint: 'rgba(242,184,201,.30)' }
  ];
  var S = { store: null, rates: null, ratesDay: null, prices: {}, canPrice: false, open: null };
  var esc = function (v) { return window.gmEscapeHtml ? gmEscapeHtml(v) : String(v == null ? '' : v); };
  var num = function (n, d) { return Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: d == null ? 2 : d, maximumFractionDigits: d == null ? 2 : d }); };
  var smart = function (n) { n = Number(n || 0); return n >= 1000 ? num(n, 0) : n >= 1 ? num(n, 2) : num(n, 4); };
  var todayKey = function () { var d = new Date(); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); };

  // ---------- data ----------
  function base() { return String((S.store && S.store.currency) || 'AED').toUpperCase(); }
  // units of X per 1 USD, with the branch's manual Syrian pound rate on top
  function ratesUSD() {
    var r = Object.assign({}, S.rates || {});
    var st = S.store || {};
    if (String(st.secondary_currency || '').toUpperCase() === 'SYP' && Number(st.secondary_currency_rate) > 0) {
      var perBase = Number(st.secondary_currency_rate), b = base();
      r.SYP = b === 'USD' ? perBase : perBase * (r[b] || 0) || r.SYP;
      r.__sypManual = true;
    }
    return r;
  }
  // how many `to` for 1 `from`
  function gmFxConvert(r, amount, from, to) { if (!r[from] || !r[to]) return null; return amount / r[from] * r[to]; }
  window.gmFxConvert = gmFxConvert;
  console.assert(Math.abs(gmFxConvert({ USD: 1, AED: 3.6725, EUR: 0.9 }, 100, 'EUR', 'AED') - 408.06) < 0.01, 'gmFxConvert');

  async function loadRates() {
    var day = todayKey();
    try { var c = JSON.parse(localStorage.getItem('gm_fx_cache') || 'null'); if (c && c.day === day && c.rates) { S.rates = c.rates; S.ratesDay = day; return; } } catch (e) {}
    try {
      var { data } = await goldmindClient.from('fx_rates_daily').select('day, rates').eq('day', day).maybeSingle();
      if (data && data.rates) { S.rates = data.rates; S.ratesDay = data.day; }
    } catch (e) {}
    if (!S.rates) {
      try {
        var res = await fetch('https://open.er-api.com/v6/latest/USD', { cache: 'no-store' });
        var j = await res.json();
        if (j && j.result === 'success' && j.rates) {
          S.rates = j.rates; S.ratesDay = day;
          goldmindClient.rpc('gm_fx_save', { p_day: day, p_rates: j.rates }).then(function () {}, function () {});
        }
      } catch (e) {}
    }
    if (!S.rates) { // offline: the latest saved day
      try { var last = (await goldmindClient.from('fx_rates_daily').select('day, rates').order('day', { ascending: false }).limit(1)).data; if (last && last[0]) { S.rates = last[0].rates; S.ratesDay = last[0].day; } } catch (e) {}
    }
    if (S.rates) try { localStorage.setItem('gm_fx_cache', JSON.stringify({ day: S.ratesDay, rates: S.rates })); } catch (e) {}
  }

  async function loadStore() {
    var sid = typeof GOLDMIND_STORE_ID !== 'undefined' ? GOLDMIND_STORE_ID : null, me = typeof GOLDMIND_STAFF_ID !== 'undefined' ? GOLDMIND_STAFF_ID : null;
    var [st, gp, staff] = await Promise.all([
      goldmindClient.from('stores').select('currency, country, secondary_currency, secondary_currency_rate, secondary_currency_rate_updated_at').eq('id', sid).maybeSingle(),
      goldmindClient.from('gold_prices').select('karat, price_per_gram').eq('store_id', sid),
      goldmindClient.from('staff').select('role, permissions').eq('id', me).maybeSingle()
    ]);
    S.store = st.data || {};
    (gp.data || []).forEach(function (p) { S.prices[p.karat] = Number(p.price_per_gram) || 0; });
    var m = staff.data; S.canPrice = !!(m && (m.role === 'owner' || (m.permissions && m.permissions.manage_gold_price === true)));
  }

  // ---------- occasions ----------
  var FIXED = {
    SY: [[1, 1, 'رأس السنة الميلادية', 'world'], [2, 14, 'عيد الحب', 'love'], [3, 18, 'عيد الثورة السورية', 'nation'], [3, 21, 'عيد الأم', 'mother'], [4, 17, 'عيد الجلاء', 'nation'], [12, 8, 'عيد التحرير', 'nation'], [12, 25, 'عيد الميلاد المجيد', 'world']],
    AE: [[1, 1, 'رأس السنة الميلادية', 'world'], [2, 14, 'عيد الحب', 'love'], [3, 21, 'عيد الأم', 'mother'], [11, 30, 'يوم الشهيد', 'nation'], [12, 2, 'عيد الاتحاد (اليوم الوطني)', 'nation']]
  };
  var HIJRI = [[10, 1, 'عيد الفطر', 'eid'], [12, 10, 'عيد الأضحى', 'eid'], [3, 12, 'المولد النبوي', 'eid']];
  var KIND = { nation: ['#2F6B47', '#E3F1E7', 'flag'], eid: ['#7A6222', '#F6EDD5', 'mosque'], mother: ['#B4436C', '#FBE6EE', 'favorite'], love: ['#C0392B', '#FCE7E4', 'volunteer_activism'], world: ['#3B5BA9', '#E6ECFA', 'event'] };
  function hijriOf(d) {
    try {
      var parts = new Intl.DateTimeFormat('en-u-ca-islamic-umalqura', { day: 'numeric', month: 'numeric' }).formatToParts(d);
      return { m: +parts.find(function (p) { return p.type === 'month'; }).value, d: +parts.find(function (p) { return p.type === 'day'; }).value };
    } catch (e) { return null; }
  }
  function gmOccasions(country, from) {
    var start = new Date(from || Date.now()); start.setHours(0, 0, 0, 0);
    var out = [], y = start.getFullYear();
    (FIXED[country] || FIXED.AE).forEach(function (f) {
      var d = new Date(y, f[0] - 1, f[1]); if (d < start) d = new Date(y + 1, f[0] - 1, f[1]);
      out.push({ t: f[2], kind: f[3], d: d });
    });
    var seen = {};
    for (var i = 0; i < 400; i++) {
      var d = new Date(start.getTime() + i * 86400000), h = hijriOf(d); if (!h) break;
      HIJRI.forEach(function (x) { if (!seen[x[2]] && h.m === x[0] && h.d === x[1]) { seen[x[2]] = 1; out.push({ t: x[2], kind: x[3], d: d, hijri: true }); } });
    }
    return out.map(function (o) { o.days = Math.round((o.d - start) / 86400000); return o; }).sort(function (a, b) { return a.days - b.days; });
  }
  window.gmOccasions = gmOccasions;
  console.assert(gmOccasions('SY', new Date(2026, 11, 7))[0].t === 'عيد التحرير', 'gmOccasions');

  // ---------- render ----------
  function country() { var c = String((S.store && S.store.country) || '').toUpperCase(); if (c === 'SY' || c === 'AE') return c; return base() === 'USD' || base() === 'SYP' ? 'SY' : 'AE'; }

  function fxHtml() {
    var r = ratesUSD(), b = base();
    if (!S.rates) return '<p class="gmt-empty">تعذّر جلب أسعار العملات الآن — تحقق من الاتصال.</p>';
    var list = MAIN.filter(function (c) { return c !== b && r[c]; });
    var opts = function (sel) { return MAIN.filter(function (c) { return r[c]; }).map(function (c) { return '<option value="' + c + '"' + (c === sel ? ' selected' : '') + '>' + c + ' — ' + CUR_AR[c] + '</option>'; }).join(''); };
    var st = S.store || {};
    var sypNote = r.__sypManual ? '<div class="gmt-note"><span class="material-symbols-outlined" aria-hidden="true">edit_note</span>الليرة السورية بسعر السوق اليدوي' + (st.secondary_currency_rate_updated_at ? ' (آخر تعديل ' + esc(gmFormatDateTime(st.secondary_currency_rate_updated_at)) + ')' : '') + (S.canPrice ? ' — <a href="gold-price-ar.html">تعديل</a>' : '') + '</div>' : '';
    return '<div class="gmt-conv">'
      + '<input type="number" inputmode="decimal" min="0" step="any" value="100" data-fx="amt" aria-label="المبلغ" dir="ltr"/>'
      + '<select data-fx="from" aria-label="من عملة">' + opts(b === 'USD' ? 'EUR' : 'USD') + '</select>'
      + '<button type="button" data-fx="swap" aria-label="تبديل العملتين" class="gmt-swap"><span class="material-symbols-outlined">swap_horiz</span></button>'
      + '<select data-fx="to" aria-label="إلى عملة">' + opts(b) + '</select>'
      + '<div class="gmt-res" data-fx="res" aria-live="polite"></div></div>'
      + '<div class="gmt-rates">' + list.map(function (c) {
        // strong currency: «1 EUR = 1.12 USD»; weak one: «1 USD = 14,000 SYP» (as said in the shop)
        var v = gmFxConvert(r, 1, c, b), txt = v >= 0.1 ? '1 ' + c + ' = ' + smart(v) + ' ' + b : '1 ' + b + ' = ' + smart(1 / v) + ' ' + c;
        return '<div class="gmt-rate"><span><b>' + c + '</b> <small>' + CUR_AR[c] + '</small></span><span dir="ltr">' + txt + '</span></div>';
      }).join('') + '</div>'
      + sypNote
      + '<div class="gmt-src">أسعار يوم ' + esc(S.ratesDay || '') + ' · open.er-api.com — تتحدث مرة يومياً</div>';
  }
  function fxCalc(box) {
    var r = ratesUSD(), q = function (k) { return box.querySelector('[data-fx="' + k + '"]'); };
    var a = Number(q('amt').value) || 0, v = gmFxConvert(r, a, q('from').value, q('to').value);
    q('res').innerHTML = v == null ? '—' : '<span dir="ltr">' + num(a, a % 1 ? 2 : 0) + ' ' + q('from').value + '</span> = <b dir="ltr">' + smart(v) + ' ' + q('to').value + '</b>';
  }

  function calcHtml() {
    var ks = [24, 22, 21, 18, 14].filter(function (k) { return S.prices[k] > 0; });
    if (!ks.length) return '<p class="gmt-empty">لا يوجد سعر ذهب معتمد بعد — يُضبط من صفحة «سعر الذهب».</p>';
    var def = ks.indexOf(18) >= 0 ? 18 : ks.indexOf(21) >= 0 ? 21 : ks[0];
    return '<div class="gmt-calc">'
      + '<label><span>الوزن (غرام)</span><input type="number" inputmode="decimal" min="0" step="any" data-c="w" placeholder="0.00" dir="ltr"/></label>'
      + '<label><span>العيار</span><div class="gmt-karats" role="group" aria-label="العيار">' + ks.map(function (k) { return '<button type="button" data-k="' + k + '" aria-pressed="' + (k === def) + '">' + k + '</button>'; }).join('') + '</div></label>'
      + '<label><span>المصنعية للغرام (' + base() + ')</span><input type="number" inputmode="decimal" min="0" step="any" data-c="f" placeholder="0" dir="ltr"/></label>'
      + '</div><div class="gmt-out" data-c="out" aria-live="polite"></div>';
  }
  function gmPiecePrice(w, gp, fab) { var g = w * gp, f = w * fab; return { gold: g, fab: f, total: g + f }; }
  window.gmPiecePrice = gmPiecePrice;
  console.assert(gmPiecePrice(10, 100, 15).total === 1150, 'gmPiecePrice');
  function calcRun(box) {
    var kb = box.querySelector('[data-k][aria-pressed="true"]'), k = kb ? Number(kb.dataset.k) : 18;
    var w = Number(box.querySelector('[data-c="w"]').value) || 0, f = Number(box.querySelector('[data-c="f"]').value) || 0, gp = S.prices[k] || 0, b = base();
    var p = gmPiecePrice(w, gp, f), r = ratesUSD(), st = S.store || {};
    var syp = String(st.secondary_currency || '').toUpperCase() === 'SYP' && b !== 'SYP' ? gmFxConvert(r, p.total, b, 'SYP') : null;
    box.querySelector('[data-c="out"]').innerHTML =
      '<div class="gmt-total"><small>سعر القطعة</small><b dir="ltr">' + num(p.total) + ' ' + b + '</b>' + (syp ? '<em dir="ltr">≈ ' + num(syp, 0) + ' SYP</em>' : '') + '</div>'
      + '<div class="gmt-break"><span>ذهب: ' + num(w, 2) + ' غ × ' + num(gp) + ' = <b dir="ltr">' + num(p.gold) + '</b></span><span>مصنعية: ' + num(w, 2) + ' غ × ' + num(f) + ' = <b dir="ltr">' + num(p.fab) + '</b></span>'
      + '<span>يعادل <b dir="ltr">' + num(w * k / 24, 3) + '</b> غ ذهب عيار 24</span></div>';
  }

  function seasonsHtml() {
    var list = gmOccasions(country()).slice(0, 8);
    var fmt = function (d) { return d.toLocaleDateString('ar', { day: 'numeric', month: 'long' }); };
    return '<div class="gmt-seasons">' + list.map(function (o) {
      var k = KIND[o.kind] || KIND.world;
      return '<div class="gmt-season" style="--k1:' + k[0] + ';--k2:' + k[1] + '"><span class="gmt-sic"><span class="material-symbols-outlined" aria-hidden="true">' + k[2] + '</span></span>'
        + '<span class="gmt-st"><b>' + esc(o.t) + '</b><small>' + fmt(o.d) + (o.hijri ? ' · تقريبي' : '') + '</small></span>'
        + '<span class="gmt-days">' + (o.days === 0 ? 'اليوم' : o.days === 1 ? 'غداً' : '<b dir="ltr">' + o.days + '</b> يوم') + '</span></div>';
    }).join('') + '</div><div class="gmt-src">' + (country() === 'SY' ? 'العطل الرسمية في سوريا' : 'العطل الرسمية في الإمارات') + ' + عيد الأم وعيد الحب · الأعياد الهجرية تقريبية (±1 يوم حسب رؤية الهلال)</div>';
  }

  function render(root) {
    root.innerHTML = '<div class="gmt-pills">' + TOOLS.map(function (t) {
      return '<button type="button" class="gmt-pill" data-tool="' + t.k + '" aria-expanded="false" aria-controls="gmt-panel-' + t.k + '-' + root.dataset.gmTools + '" style="--c1:' + t.c1 + ';--c2:' + t.c2 + ';--tint:' + t.tint + '">'
        + '<span class="gmt-ic"><span class="material-symbols-outlined" aria-hidden="true">' + t.ic + '</span></span>'
        + '<span class="gmt-tx"><b>' + t.t + '</b><small>' + t.s + '</small></span>'
        + '<span class="material-symbols-outlined gmt-chev" aria-hidden="true">expand_more</span></button>';
    }).join('') + '</div>' + TOOLS.map(function (t) {
      return '<div class="gmt-panel" id="gmt-panel-' + t.k + '-' + root.dataset.gmTools + '" data-panel="' + t.k + '" hidden style="--c1:' + t.c1 + ';--tint:' + t.tint + '"></div>';
    }).join('');
    root.addEventListener('click', function (e) {
      var pill = e.target.closest('.gmt-pill');
      if (pill) return toggle(root, pill.dataset.tool);
      var sw = e.target.closest('[data-fx="swap"]');
      if (sw) { var box = sw.closest('.gmt-panel'), a = box.querySelector('[data-fx="from"]'), b = box.querySelector('[data-fx="to"]'), x = a.value; a.value = b.value; b.value = x; fxCalc(box); return; }
      var kb = e.target.closest('[data-k]');
      if (kb) { kb.parentNode.querySelectorAll('[data-k]').forEach(function (b) { b.setAttribute('aria-pressed', String(b === kb)); }); calcRun(kb.closest('.gmt-panel')); }
    });
    root.addEventListener('input', function (e) {
      var p = e.target.closest('.gmt-panel'); if (!p) return;
      if (p.dataset.panel === 'fx') fxCalc(p); else if (p.dataset.panel === 'calc') calcRun(p);
    });
  }
  async function toggle(root, k) {
    var willOpen = root.dataset.open !== k;
    root.dataset.open = willOpen ? k : '';
    root.querySelectorAll('.gmt-pill').forEach(function (p) { p.setAttribute('aria-expanded', String(willOpen && p.dataset.tool === k)); });
    root.querySelectorAll('.gmt-panel').forEach(function (p) { p.hidden = !(willOpen && p.dataset.panel === k); });
    if (!willOpen) return;
    var panel = root.querySelector('[data-panel="' + k + '"]');
    panel.innerHTML = '<p class="gmt-empty">جارِ التحميل...</p>';
    await ready;
    if (k === 'fx') { if (!S.rates) await loadRates(); panel.innerHTML = fxHtml(); if (S.rates) fxCalc(panel); }
    else if (k === 'calc') { panel.innerHTML = calcHtml(); if (panel.querySelector('[data-c="w"]')) { calcRun(panel); panel.querySelector('[data-c="w"]').focus(); } }
    else panel.innerHTML = seasonsHtml();
  }

  var ready = (async function () {
    var ok = function () { return typeof GOLDMIND_STAFF_ID !== 'undefined' && GOLDMIND_STAFF_ID && GOLDMIND_STORE_ID && typeof goldmindClient !== 'undefined'; };
    for (var i = 0; i < 60 && !ok(); i++) await new Promise(function (r) { setTimeout(r, 250); });
    if (ok()) { try { await loadStore(); } catch (e) {} }
  })();

  function init() { document.querySelectorAll('[data-gm-tools]').forEach(render); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
