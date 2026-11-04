// Home page charts (computer and phone):
//  1. بورصة الذهب — XAU/USD candles (TradingView chart, OANDA spot), 5 min / 15 min / 1 hour.
//     Loaded only when its box is on screen; the chosen candle size is remembered per device.
//  2. المبيعات اليومية — last 30 days, one bar per day, with last 7 days vs the 7 before.
//  3. مبيعات الموظفين — last 7 days per salesperson, highest first.
// Sales charts: owner or staff with «view_reports» only.
(function () {
  var TF_KEY = 'gm_gold_chart_tf';
  var TFS = [['5', '5 د'], ['15', '15 د'], ['60', 'ساعة']];
  function tf() { try { var v = localStorage.getItem(TF_KEY); return TFS.some(function (t) { return t[0] === v; }) ? v : '15'; } catch (e) { return '15'; } }
  function esc(s) { return window.gmEscapeHtml ? gmEscapeHtml(s) : String(s == null ? '' : s); }
  function money(n) { return Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 }); }

  // ---------- gold chart ----------
  function mountGold(box) {
    var interval = tf();
    box.querySelectorAll('[data-tf]').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.tf === interval)); });
    var host = box.querySelector('.gmc-gold-host');
    host.innerHTML = '';
    var w = document.createElement('div'); w.className = 'tradingview-widget-container'; w.style.cssText = 'height:100%;width:100%';
    var inner = document.createElement('div'); inner.className = 'tradingview-widget-container__widget'; inner.style.cssText = 'height:100%;width:100%';
    w.appendChild(inner);
    var s = document.createElement('script');
    s.src = 'https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js';
    s.async = true;
    s.text = JSON.stringify({ autosize: true, symbol: 'OANDA:XAUUSD', interval: interval, timezone: 'Asia/Dubai', theme: 'light', style: '1', locale: 'ar_AE',
      hide_top_toolbar: true, hide_legend: false, hide_side_toolbar: true, allow_symbol_change: false, save_image: false, calendar: false, withdateranges: false,
      backgroundColor: 'rgba(255,255,255,1)', support_host: 'https://www.tradingview.com' });
    w.appendChild(s);
    host.appendChild(w);
    box.dataset.loaded = interval;
  }
  function setupGold(box) {
    var seg = box.querySelector('.gmc-seg');
    seg.innerHTML = TFS.map(function (t) { return '<button type="button" data-tf="' + t[0] + '" aria-pressed="false">' + t[1] + '</button>'; }).join('');
    seg.addEventListener('click', function (e) {
      var b = e.target.closest('[data-tf]'); if (!b) return;
      try { localStorage.setItem(TF_KEY, b.dataset.tf); } catch (x) {}
      mountGold(box);
    });
    var load = function () { if (!box.dataset.loaded && box.offsetParent !== null) mountGold(box); };
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (en, ob) { if (en.some(function (x) { return x.isIntersecting; })) { load(); if (box.dataset.loaded) ob.disconnect(); } }, { rootMargin: '200px' }).observe(box);
    } else load();
  }

  // ---------- sales charts ----------
  // rows: [{created_at, total_amount, seller}] → 30 days and per-seller (last 7 days)
  function gmSalesSeries(rows, now) {
    var day = function (d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x.getTime(); };
    var today = day(now || Date.now()), DAY = 86400000, days = [];
    for (var i = 29; i >= 0; i--) days.push({ t: today - i * DAY, v: 0, n: 0 });
    var idx = {}; days.forEach(function (d, i) { idx[d.t] = i; });
    var sellers = {};
    rows.forEach(function (r) {
      var t = day(r.created_at), i = idx[t], v = Number(r.total_amount) || 0;
      if (i == null) return;
      days[i].v += v; days[i].n++;
      if (t > today - 7 * DAY) { var s = sellers[r.seller] || (sellers[r.seller] = { id: r.seller, v: 0, n: 0 }); s.v += v; s.n++; }
    });
    var last7 = days.slice(-7).reduce(function (a, d) { return a + d.v; }, 0), prev7 = days.slice(-14, -7).reduce(function (a, d) { return a + d.v; }, 0);
    return { days: days, last7: last7, prev7: prev7, sellers: Object.keys(sellers).map(function (k) { return sellers[k]; }).sort(function (a, b) { return b.v - a.v; }) };
  }
  window.gmSalesSeries = gmSalesSeries;
  console.assert((function () { var r = gmSalesSeries([{ created_at: Date.now(), total_amount: 100, seller: 'a' }, { created_at: Date.now() - 8 * 86400000, total_amount: 50, seller: 'a' }]); return r.last7 === 100 && r.prev7 === 50 && r.sellers[0].v === 100; })(), 'gmSalesSeries');

  function renderSales(box, S, names, cur) {
    var max = Math.max.apply(null, S.days.map(function (d) { return d.v; }).concat([1]));
    var ch = S.prev7 > 0 ? (S.last7 - S.prev7) / S.prev7 * 100 : null;
    var chHtml = ch == null ? '' : '<span class="gmc-chg ' + (ch >= 0 ? 'up' : 'down') + '">' + (ch >= 0 ? '▲ ' : '▼ ') + Math.abs(ch).toFixed(0) + '%</span>';
    var dfmt = function (t) { var d = new Date(t); return d.getDate() + '/' + (d.getMonth() + 1); };
    var bars = S.days.map(function (d, i) {
      var h = d.v > 0 ? Math.max(3, Math.round(d.v / max * 100)) : 0;
      return '<div class="gmc-bar' + (i === S.days.length - 1 ? ' today' : '') + '" title="' + dfmt(d.t) + ' — ' + money(d.v) + ' ' + cur + ' (' + d.n + ' فاتورة)"><i style="height:' + h + '%"></i></div>';
    }).join('');
    var smax = Math.max.apply(null, S.sellers.map(function (s) { return s.v; }).concat([1]));
    var sellers = S.sellers.length ? S.sellers.map(function (s, i) {
      return '<div class="gmc-srow"><span class="gmc-sname">' + (i === 0 ? '<span class="material-symbols-outlined" aria-hidden="true" style="font-size:15px;color:#B4955A">emoji_events</span>' : '') + esc(names[s.id] || 'غير محدد') + '</span>'
        + '<span class="gmc-strack"><i style="width:' + Math.max(2, Math.round(s.v / smax * 100)) + '%"></i></span>'
        + '<span class="gmc-sval"><b dir="ltr">' + money(s.v) + '</b> <small>' + s.n + ' فاتورة</small></span></div>';
    }).join('') : '<p class="gmc-empty">لا مبيعات في آخر 7 أيام.</p>';
    box.querySelector('.gmc-sales-body').innerHTML =
      '<div class="gmc-block"><div class="gmc-bh"><b>المبيعات اليومية</b><span>آخر 30 يوماً · ' + cur + '</span></div>'
      + '<div class="gmc-kpi">آخر 7 أيام: <b dir="ltr">' + money(S.last7) + '</b> ' + chHtml + ' <small>مقابل ' + money(S.prev7) + ' في الأسبوع الذي قبله</small></div>'
      + '<div class="gmc-bars" role="img" aria-label="المبيعات اليومية لآخر 30 يوماً">' + bars + '</div>'
      + '<div class="gmc-axis"><span>' + dfmt(S.days[0].t) + '</span><span>اليوم</span></div></div>'
      + '<div class="gmc-block"><div class="gmc-bh"><b>مبيعات الموظفين</b><span>آخر 7 أيام · ' + cur + '</span></div>' + sellers + '</div>';
  }

  async function setupSales(boxes) {
    // session globals are top-level `let`s in supabase-config.js (not window properties)
    var ready = function () { return typeof GOLDMIND_STAFF_ID !== 'undefined' && GOLDMIND_STAFF_ID && GOLDMIND_STORE_ID && typeof goldmindClient !== 'undefined'; };
    for (var i = 0; i < 60 && !ready(); i++) await new Promise(function (r) { setTimeout(r, 250); });
    if (!ready()) return;
    var me = (await goldmindClient.from('staff').select('role, permissions').eq('id', GOLDMIND_STAFF_ID).maybeSingle()).data;
    if (!(me && (me.role === 'owner' || (me.permissions && me.permissions.view_reports === true)))) return;
    boxes.forEach(function (b) { b.classList.remove('hidden'); });
    var since = new Date(); since.setHours(0, 0, 0, 0); since = new Date(since.getTime() - 29 * 86400000);
    var res = await gmFetchAllRows(function () {
      return goldmindClient.from('invoices').select('id, created_at, total_amount, salesperson_id, created_by, currency')
        .eq('store_id', GOLDMIND_STORE_ID).eq('type', 'sale').neq('status', 'cancelled').gte('created_at', since.toISOString()).order('id');
    });
    if (res.error) { boxes.forEach(function (b) { b.querySelector('.gmc-sales-body').innerHTML = '<p class="gmc-empty">تعذّر تحميل المبيعات.</p>'; }); return; }
    var rows = (res.data || []).map(function (r) { return { created_at: r.created_at, total_amount: r.total_amount, seller: r.salesperson_id || r.created_by, currency: r.currency }; });
    var ids = rows.map(function (r) { return r.seller; }).filter(function (v, i, a) { return v && a.indexOf(v) === i; });
    var names = {};
    if (ids.length) ((await goldmindClient.from('staff').select('id, full_name').in('id', ids)).data || []).forEach(function (s) { names[s.id] = s.full_name; });
    var cur = (rows[0] && rows[0].currency) || '';
    if (!cur) { var st = (await goldmindClient.from('stores').select('currency').eq('id', GOLDMIND_STORE_ID).maybeSingle()).data; cur = (st && st.currency) || 'AED'; }
    var S = gmSalesSeries(rows);
    boxes.forEach(function (b) { renderSales(b, S, names, String(cur).toUpperCase()); });
  }

  function init() {
    document.querySelectorAll('[data-gmc-gold]').forEach(setupGold);
    var sales = [].slice.call(document.querySelectorAll('[data-gmc-sales]'));
    if (sales.length) setupSales(sales);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
