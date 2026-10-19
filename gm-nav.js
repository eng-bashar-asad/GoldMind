// GoldMind — one side menu for every page (2026-09-30).
// Before this, only the home screen had the full dark menu; other pages had a
// back arrow on phones and a partial 16-link strip on laptops. This file owns
// the menu contents and the drawer, and is loaded by theme.js on every page.
(function () {
  var page = location.pathname.split('/').pop() || 'index-ar.html';
  var SKIP = ['login-entry-ar.html', 'login-ar-4.html', 'auth-callback-ar.html', 'admin-login-ar.html', 'admin-panel-ar.html', 'landing-ar.html',
    'privacy-policy-ar.html', 'terms-ar.html', 'company-register-ar.html', 'privacy-accept-ar.html', 'invoice-receipt-ar.html',
    'invoice-receipt-policy-ar.html', 'switch-branch-ar.html', 'payroll-success-ar.html'];
  if (SKIP.indexOf(page) !== -1 || window.GM_NAV_DISABLED) return;

  // p: permission key (owner always sees everything; hiding is cosmetic, each page still checks access)
  var GROUPS = [
    { t: 'الرئيسية', i: 'home', l: [
      ['index-ar.html', 'dashboard', 'الشاشة الرئيسية'],
      ['new-sale-ar.html', 'add_shopping_cart', 'بيع جديد / فاتورة', 'create_invoice'],
      ['create-invoice-v2-ar.html', 'local_shipping', 'فاتورة شراء', 'create_invoice'],
      ['sales-return-ar.html', 'keyboard_return', 'مرتجع مبيعات', 'create_invoice'] ] },
    { t: 'الفواتير والعملاء', i: 'receipt_long', l: [
      ['invoices-list-ar.html', 'list_alt', 'كل الفواتير', 'view_invoices'],
      ['invoices-archive-ar.html', 'inventory', 'الأرشيف الشامل', 'view_invoices'],
      ['customers-ar.html', 'person', 'الزبائن (أفراد وشركات)', 'view_customers'],
      ['ledger-ar.html', 'handshake', 'التجار', 'view_traders'],
      ['deposits-ar.html', 'bookmark_added', 'سندات العربون', 'edit_customers|manage_daily_cashbox'],
      ['repairs-ar.html', 'build', 'الصيانة والتصليح', 'view_repairs'] ] },
    { t: 'المستودعات', i: 'inventory_2', l: [
      ['inventory-list-ar.html', 'inventory_2', 'المخزن', 'view_inventory'],
      ['inventory-add.html', 'add_box', 'إضافة قطعة للمخزون', 'add_piece'],
      ['inventory-count-ar.html', 'checklist', 'الجرد', 'run_inventory_count'],
      ['stock-production-ar.html', 'precision_manufacturing', 'إنتاج القطع من رصيد الجملة', 'add_piece'],
      ['opening-stock-ar.html', 'warehouse', 'بضاعة أول المدة', 'add_piece'],
      ['stock-transfer-ar.html', 'swap_vert', 'إخراج / إدخال بضاعة', 'view_inventory'],
      ['diamond-inventory-list-ar.html', 'diamond', 'مخزون الألماس', 'view_inventory'],
      ['diamond-inventory-add.html', 'diamond', 'إضافة ألماسة', 'add_piece'],
      ['diamond-stock-production-ar.html', 'diamond', 'إنتاج قطع الألماس', 'add_piece'] ] },
    { t: 'المالية', i: 'account_balance_wallet', l: [
      ['daily-cashbox-ar.html', 'point_of_sale', 'الصندوق اليومي', 'manage_daily_cashbox'],
      ['cash-voucher-ar.html', 'swap_vert', 'سند قبض / صرف', 'manage_daily_cashbox|edit_customers|edit_traders'],
      ['expense-entry-ar.html', 'receipt', 'المصاريف', 'manage_daily_cashbox|view_profit_report|give_gifts'],
      ['expense-entry-ar.html?type=gifts', 'redeem', 'إخراج هدايا', 'give_gifts'],
      ['main-cashbox-ar.html', 'account_balance', 'الصندوق الرئيسي', 'manage_daily_cashbox'],
      ['company-balances-ar.html', 'account_balance', 'أرصدة الشركة', 'view_reports'],
      ['gold-price-ar.html', 'payments', 'سعر الذهب', 'manage_gold_price'] ] },
    { t: 'التقارير', i: 'bar_chart', l: [
      ['financial-report-ar.html', 'summarize', 'التقرير المالي الشامل', 'view_reports'],
      ['profit-report-ar.html', 'trending_up', 'تقرير الأرباح', 'view_profit_report'],
      ['reports-ar.html', 'bar_chart', 'التقارير والتحليلات', 'view_reports'],
      ['tax-report-ar.html', 'receipt_long', 'كشف الضريبة', 'view_reports'],
      ['accounting-check-ar.html', 'fact_check', 'فحص الحسابات', 'view_reports'],
      ['audit-log-ar.html', 'history', 'سجل النشاط', 'view_reports'] ] },
    { t: 'الموظفون', i: 'badge', l: [
      ['staff-permissions-ar.html', 'badge', 'الموظفون والصلاحيات', 'manage_staff'],
      ['payroll-ar.html', 'payments', 'الرواتب', 'manage_payroll'],
      ['hr-employees-ar.html', 'badge', 'سجل الموظفين والإجازات', 'manage_payroll'] ] },
    { t: 'التوثيق (KYC)', i: 'verified_user', l: [
      ['kyc-screening-ar.html', 'fact_check', 'فحص القوائم الرسمية', 'view_customers'],
      ['kyc-companies-ar.html', 'domain_verification', 'مستندات الشركات', 'view_customers'],
      ['kyc-individuals-ar.html', 'badge', 'مستندات الأفراد', 'view_customers'] ] },
    { t: 'الإعدادات', i: 'settings', l: [
      ['settings-ar.html', 'settings', 'الإعدادات'],
      ['company-settings-ar.html', 'store', 'إعدادات الشركة', 'edit_settings'],
      ['devices-setup-ar.html', 'print', 'إعداد الأجهزة'],
      ['theme-picker-ar.html', 'palette', 'مظهر التطبيق'],
      ['account-security-ar.html', 'lock', 'الأمان وكلمة المرور'],
      ['fiscal-year-close-ar.html', 'event_repeat', 'إغلاق السنة المالية', 'edit_settings'],
      ['subscription-ar.html', 'workspace_premium', 'الاشتراك', 'manage_subscription'],
      ['support-contact-ar.html', 'support_agent', 'تواصل مع الدعم'],
      ['#tz', 'schedule', 'المنطقة الزمنية للعرض'] ] },
    { t: 'الأدلة والشروحات', i: 'menu_book', l: [
      ['guides-ar.html', 'menu_book', 'كل الأدلة'],
      ['rfid-guide-ar.html', 'nfc', 'دليل RFID: البرمجة والجرد'] ] }
  ];
  window.GM_NAV_GROUPS = GROUPS;
  // computer layout on for every page with the menu; the sale screen starts with the small bar
  document.documentElement.classList.add('gm-desk');
  // below 1280px (small laptops) the bar is always the small one so the page keeps its width
  function gmMiniPref() {
    var mini = null;
    try { mini = localStorage.getItem('gm_nav_mini'); } catch (e) { /* ignore */ }
    var narrow = window.matchMedia && window.matchMedia('(max-width: 1279px)').matches;
    document.documentElement.classList.toggle('gm-mini', narrow || mini === '1' || (mini === null && page === 'new-sale-ar.html'));
  }
  gmMiniPref();
  window.addEventListener('resize', gmMiniPref);

  var css = document.createElement('style');
  css.textContent = `
    #gmNav{position:fixed;top:0;right:0;height:100%;width:316px;max-width:86vw;z-index:301;background:#17140F;color:#F3EEDF;
      border-radius:28px 0 0 28px;transform:translateX(100%);transition:transform .45s cubic-bezier(.22,1,.36,1),box-shadow .45s;
      display:flex;flex-direction:column;direction:rtl;font-family:inherit}
    #gmNav.open{transform:none;box-shadow:-24px 0 60px rgba(0,0,0,.45)}
    #gmNavOverlay{position:fixed;inset:0;z-index:300;background:rgba(12,10,7,.42);-webkit-backdrop-filter:blur(3px);backdrop-filter:blur(3px);display:none}
    #gmNavOverlay.open{display:block}
    #gmNav .gn-head{display:flex;align-items:center;justify-content:space-between;padding:18px 18px 12px;border-bottom:1px solid #2A251C}
    #gmNav .gn-head b{font-size:17px;color:#E9CF8B}
    #gmNav .gn-x{width:38px;height:38px;border-radius:12px;border:0;background:#2A251C;color:#F3EEDF;display:flex;align-items:center;justify-content:center}
    #gmNav nav{flex:1;overflow-y:auto;padding:8px 0}
    #gmNav .gn-h{width:100%;height:48px;border:0;background:transparent;color:#F3EEDF;display:flex;align-items:center;gap:10px;padding:0 20px;font-size:15px;font-weight:600;text-align:right;font-family:inherit}
    #gmNav .gn-h .gn-ic{color:#D9B45A}
    #gmNav .gn-h .gn-chev{margin-inline-start:auto;color:#8C8270;transition:transform .3s}
    #gmNav .gn-g.open .gn-chev{transform:rotate(180deg)}
    #gmNav .gn-b{display:grid;grid-template-rows:0fr;transition:grid-template-rows .3s cubic-bezier(.22,1,.36,1)}
    #gmNav .gn-g.open .gn-b{grid-template-rows:1fr}
    #gmNav .gn-b>div{overflow:hidden}
    #gmNav a.gn-a{display:flex;align-items:center;gap:12px;margin:2px 12px;padding:10px 14px;border-radius:12px;color:#E6DECB;text-decoration:none;font-size:14px}
    #gmNav a.gn-a:hover{background:rgba(217,180,90,.08)}
    #gmNav a.gn-a .material-symbols-outlined{color:#BFB39A;font-size:20px}
    #gmNav a.gn-a.here{background:#D9B45A;color:#17140F}
    #gmNav a.gn-a.here .material-symbols-outlined{color:#17140F}
    #gmNav .gn-foot{border-top:1px solid #2A251C;padding:8px}
    #gmNav .gn-out{width:100%;display:flex;align-items:center;gap:10px;padding:12px 16px;border:0;background:transparent;color:#F2A99C;font-size:14px;font-weight:600;font-family:inherit}
    .gm-nav-btn{width:40px;height:40px;min-width:40px;border-radius:12px;border:0;display:inline-flex;align-items:center;justify-content:center;flex:none;
      background:linear-gradient(125deg,#c89a3c,#f6e2a6 40%,#d4a64a 60%,#b58a33);color:#2A1F08;cursor:pointer}
    .gm-nav-btn .material-symbols-outlined{font-size:22px}
    body.gm-nav-open{overflow:hidden}
    @media print{#gmNav,#gmNavOverlay,.gm-nav-btn{display:none!important}}
    /* computer (>=1024px): the menu is a fixed side bar on the right, the page sits beside it,
       and the phone's bottom tab bar and menu buttons go away (design "GoldMind — تصميم الكمبيوتر") */
    #gmNav .gn-mini{display:none}
    @media screen and (min-width:1024px){
      html.gm-desk body{padding-right:var(--gm-side,264px)!important}
      html.gm-desk #gmNav{transform:none;width:var(--gm-side,264px);max-width:none;border-radius:0;box-shadow:none;z-index:45;transition:width .25s}
      html.gm-desk #gmNav .gn-x{display:none}
      html.gm-desk #gmNav .gn-mini{display:flex}
      html.gm-desk #gmNavOverlay{display:none!important}
      html.gm-desk .gm-nav-btn,html.gm-desk [onclick*="openNavDrawer"]{display:none!important}
      html.gm-desk body.gm-nav-open{overflow:auto}
      html.gm-desk nav.fixed.bottom-0.justify-around,html.gm-desk .gm-bottom-tabs{display:none!important}
      html.gm-desk .fixed.w-full:not(.inset-0),html.gm-desk .fixed.inset-x-0:not(.inset-0){right:var(--gm-side,264px)!important;left:0!important;width:auto!important}
      html.gm-desk body.pb-24,html.gm-desk main.pb-24,html.gm-desk main.pb-32{padding-bottom:32px}
      html.gm-desk.gm-mini{--gm-side:76px}
      html.gm-desk.gm-mini #gmNav .gn-head b,html.gm-desk.gm-mini #gmNav .gn-h>span:not(.gn-ic),html.gm-desk.gm-mini #gmNav a.gn-a>span:not(.material-symbols-outlined),html.gm-desk.gm-mini #gmNav .gn-out span+*{display:none}
      html.gm-desk.gm-mini #gmNav .gn-head{justify-content:center;padding:18px 0 12px}
      html.gm-desk.gm-mini #gmNav .gn-h{justify-content:center;padding:0}
      html.gm-desk.gm-mini #gmNav a.gn-a{justify-content:center;margin:2px 8px;padding:10px 0}
      html.gm-desk.gm-mini #gmNav .gn-out{justify-content:center;font-size:0}
    }
    /* desktop form grid: add class gm-dform to a form's column; wrap inner groups with gm-group,
       mark rows that must span the whole width with gm-full (textareas, titles, toggles, buttons do it on their own) */
    @media screen and (min-width:1024px){
      .gm-dform:not(.hidden){display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr));gap:22px 18px;align-items:start}
      .gm-dform.gm-cols-2{grid-template-columns:repeat(2,minmax(0,1fr))}
      .gm-dform>.gm-group:not(.hidden){display:contents!important}
      .gm-dform .gm-full,.gm-dform .gm-section-title,.gm-dform>h2,.gm-dform>h3,.gm-dform>.gm-group>h2,.gm-dform>.gm-group>h3,.gm-dform>p,.gm-dform>.gm-group>p,.gm-dform>:has(textarea),.gm-dform>.gm-group>:has(textarea),
      .gm-dform>label:has(input[type=checkbox]),.gm-dform>.gm-group>label:has(input[type=checkbox]),
      .gm-dform>:has(>button.w-full),.gm-dform>[id$=message],.gm-dform>[id$=msg]{grid-column:1/-1}
      .gm-dform>details,.gm-dform>fieldset,.gm-dform>.gm-box{grid-column:1/-1}
      .gm-dform>details>div.flex-col{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px 18px;align-items:start}
      .gm-dform>details>div.flex-col>p,.gm-dform>details>div.flex-col>.grid,.gm-dform>details>div.flex-col>:has(textarea),.gm-dform>details>div.flex-col>[id$=list]{grid-column:1/-1}
      .gm-dform>button.w-full,.gm-dform>a.w-full{grid-column:1/-1;max-width:360px}
      .gm-dform .gm-span2{grid-column:span 2}
      .gm-dform input,.gm-dform select,.gm-dform>*,.gm-dform>.gm-group>*{min-width:0}
      .gm-dform>:has(>button.w-full)>button.w-full{max-width:360px}
      .gm-dform .gm-section-title{margin-top:6px}
      /* desktop card columns: add gm-dcols to a page's stack of cards (gm-c3 for three); gm-full spans the row */
      .gm-dcols:not(.hidden){display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px;align-items:start}
      .gm-dcols.gm-c3:not(.hidden){grid-template-columns:repeat(3,minmax(0,1fr))}
      .gm-dcols>.gm-full,.gm-dcols>h1,.gm-dcols>h2,.gm-dcols>p:first-child{grid-column:1/-1}
      .gm-dcols>*{margin-top:0!important}
      .gm-dcols>button.w-full,.gm-dcols>p[id]{grid-column:1/-1}
      .gm-dcols>button.w-full{max-width:360px}
      /* desktop split: the gm-side card (a form or summary) on the right, everything else beside it */
      .gm-dsplit:not(.hidden){display:grid!important;grid-template-columns:minmax(340px,420px) minmax(0,1fr);gap:16px 24px;align-items:start;grid-auto-flow:row dense}
      .gm-dsplit>*{grid-column:2;margin-top:0!important;min-width:0}
      .gm-dsplit>.gm-side{grid-column:1;grid-row:1/span 30;position:sticky;top:84px}
      .gm-dsplit>.gm-full{grid-column:1/-1}
    }
    /* phone bottom tabs (designs MHome / MStock / MCustomers): الرئيسية، المخزن، [بيع]، الزبائن، الفواتير.
       A page puts <nav class="gm-bottom-tabs"></nav>; it is filled below. */
    .gm-bottom-tabs{position:fixed;bottom:0;inset-inline:0;z-index:50;display:flex;align-items:center;padding:0 6px env(safe-area-inset-bottom);height:calc(68px + env(safe-area-inset-bottom));background:var(--gm-bg-elevated,#fff);background:#FFFFFF;border-top:1px solid #E4DAC0;box-shadow:0 -2px 10px rgba(28,26,22,.05)}
    .gm-tab{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;min-height:48px;font-size:10.5px;color:#6B6355;text-decoration:none}
    .gm-tab.gm-tab-on{color:#211D17;font-weight:700}
    .gm-tab.gm-tab-on .material-symbols-outlined{font-variation-settings:'FILL' 1}
    .gm-tab-sale{flex:none;width:62px;height:62px;margin-top:-30px;border-radius:20px;background:#1C1A16;color:#E9CF8B;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1px;font-size:10.5px;font-weight:700;text-decoration:none;box-shadow:0 8px 18px rgba(28,26,22,.25)}
    .gm-tab-sale .material-symbols-outlined{font-size:26px}
    /* loading placeholder (idea from 21st.dev skeletons): every page's #loading-state shows shimmering bars, the text stays for screen readers */
    #loading-state:not(.hidden){position:relative;color:transparent!important;min-height:180px;padding:24px 0!important}
    #loading-state:not(.hidden)::before,#loading-state:not(.hidden)::after{content:'';position:absolute;inset-inline:0;border-radius:16px;
      background:linear-gradient(100deg,rgba(201,185,143,.18) 30%,rgba(255,255,255,.65) 50%,rgba(201,185,143,.18) 70%);background-size:300% 100%;animation:gmSkel 1.4s ease-in-out infinite}
    #loading-state:not(.hidden)::before{top:20px;height:74px}
    #loading-state:not(.hidden)::after{top:110px;height:48px;inset-inline-end:30%}
    @keyframes gmSkel{from{background-position:100% 0}to{background-position:0 0}}
    @media (prefers-reduced-motion:reduce){#loading-state::before,#loading-state::after{animation:none!important}}
    /* phone floating add button */
    .gm-fab{position:fixed;inset-inline-end:16px;bottom:calc(86px + env(safe-area-inset-bottom));z-index:49;width:58px;height:58px;border-radius:18px;background:#7A6640;color:#fff;display:flex;align-items:center;justify-content:center;box-shadow:0 8px 18px rgba(28,26,22,.25)}
    .gm-fab .material-symbols-outlined{font-size:28px}
    @media screen and (min-width:1024px){.gm-fab{display:none!important}}
    #gmNav .gn-mini{width:38px;height:38px;border-radius:12px;border:0;background:#2A251C;color:#F3EEDF;align-items:center;justify-content:center;cursor:pointer}
    @media (prefers-reduced-motion:reduce){#gmNav,#gmNav .gn-b,#gmNav .gn-chev{transition:none!important}}
  `;
  document.head.appendChild(css);

  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  var TABS = [['index-ar.html', 'dashboard', 'الرئيسية'], ['inventory-list-ar.html', 'inventory_2', 'المخزن'], null,
    ['customers-ar.html', 'person', 'الزبائن'], ['invoices-list-ar.html', 'receipt_long', 'الفواتير']];
  function fillTabs() {
    document.querySelectorAll('nav.gm-bottom-tabs').forEach(function (n) {
      if (n.children.length) return;
      if (!n.getAttribute('aria-label')) n.setAttribute('aria-label', 'التنقل');
      n.innerHTML = TABS.map(function (t) {
        if (!t) return '<a class="gm-tab-sale" href="new-sale-ar.html" aria-label="بيع جديد"><span class="material-symbols-outlined">add</span>بيع</a>';
        var on = t[0] === page;
        return '<a class="gm-tab' + (on ? ' gm-tab-on' : '') + '" href="' + t[0] + '"' + (on ? ' aria-current="page"' : '') + '><span class="material-symbols-outlined">' + t[1] + '</span>' + t[2] + '</a>';
      }).join('');
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fillTabs); else fillTabs();
  window.gmFillTabs = fillTabs;

  // count a number up to its value once (idea from 21st.dev "number ticker"); keeps the text around the number (currency, units).
  // If the page writes a new value meanwhile, the count stops and the new value stays.
  window.gmTick = function (el, ms) {
    if (!el || !el.textContent || el.__gmTicking) return;
    var txt = el.textContent, m = txt.match(/-?[\d,]+(\.\d+)?/);
    if (!m || el.dataset.gmTicked === txt) return;
    el.dataset.gmTicked = txt;
    var end = parseFloat(m[0].replace(/,/g, '')), dec = m[1] ? m[1].length - 1 : 0;
    if (!isFinite(end) || Math.abs(end) < 1 || (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)) return;
    var t0 = null, d = ms || 700, pre = txt.slice(0, m.index), post = txt.slice(m.index + m[0].length), last = txt;
    function f(v) { return v.toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec }); }
    function step(t) {
      if (el.textContent !== last) { el.__gmTicking = false; return; } // the page wrote a newer value
      t0 = t0 || t; var k = Math.min(1, (t - t0) / d); k = 1 - Math.pow(1 - k, 3);
      last = k < 1 ? pre + f(end * k) + post : txt;
      el.textContent = last;
      if (k < 1) requestAnimationFrame(step); else el.__gmTicking = false;
    }
    el.__gmTicking = true;
    requestAnimationFrame(step);
  };

  function build() {
    var ov = document.createElement('div'); ov.id = 'gmNavOverlay';
    var d = document.createElement('aside'); d.id = 'gmNav'; d.setAttribute('aria-label', 'القائمة'); d.setAttribute('aria-hidden', 'true');
    var html = '<div class="gn-head"><b>GoldMind</b><button type="button" class="gn-mini" aria-label="تصغير القائمة" title="تصغير / توسيع القائمة"><span class="material-symbols-outlined">dock_to_left</span></button><button type="button" class="gn-x" aria-label="إغلاق القائمة"><span class="material-symbols-outlined">close</span></button></div><nav>';
    GROUPS.forEach(function (g) {
      var here = g.l.some(function (x) { return x[0] === page; });
      html += '<div class="gn-g' + (here ? ' open here-g' : '') + '"><button type="button" class="gn-h" aria-expanded="' + here + '"><span class="material-symbols-outlined gn-ic">' + g.i + '</span><span>' + esc(g.t) + '</span><span class="material-symbols-outlined gn-chev">expand_more</span></button><div class="gn-b"><div>';
      g.l.forEach(function (x) {
        html += '<a class="gn-a' + (x[0] === page ? ' here' : '') + '" href="' + x[0] + '"' + (x[3] ? ' data-nav-perm="' + x[3] + '"' : '') + '><span class="material-symbols-outlined">' + x[1] + '</span><span>' + esc(x[2]) + '</span></a>';
      });
      html += '</div></div></div>';
    });
    html += '</nav><div class="gn-foot"><button type="button" class="gn-out"><span class="material-symbols-outlined">logout</span>تسجيل الخروج</button></div>';
    d.innerHTML = html;
    document.body.appendChild(ov); document.body.appendChild(d);

    ov.addEventListener('click', close);
    d.querySelector('.gn-mini').addEventListener('click', function () {
      var mini = !document.documentElement.classList.contains('gm-mini');
      document.documentElement.classList.toggle('gm-mini', mini);
      try { localStorage.setItem('gm_nav_mini', mini ? '1' : ''); } catch (e) { /* ignore */ }
    });
    // in the small bar a link shows its name on hover
    d.querySelectorAll('a.gn-a').forEach(function (a) { a.title = a.textContent.trim(); });
    d.querySelector('.gn-x').addEventListener('click', close);
    d.querySelector('.gn-out').addEventListener('click', function () { if (typeof goldMindSignOut === 'function') goldMindSignOut(); });
    d.querySelectorAll('.gn-h').forEach(function (b) {
      b.addEventListener('click', function () {
        var g = b.parentNode, open = !g.classList.contains('open');
        d.querySelectorAll('.gn-g.open').forEach(function (o) { if (o !== g) { o.classList.remove('open'); o.querySelector('.gn-h').setAttribute('aria-expanded', 'false'); } });
        g.classList.toggle('open', open); b.setAttribute('aria-expanded', String(open));
      });
    });
    var tz = d.querySelector('a[href="#tz"]');
    if (tz) tz.addEventListener('click', function (e) { e.preventDefault(); close(); if (typeof gmOpenTimezonePicker === 'function') gmOpenTimezonePicker(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && d.classList.contains('open')) close(); });
  }

  function open() {
    var d = document.getElementById('gmNav'); if (!d) return;
    d.classList.add('open'); d.setAttribute('aria-hidden', 'false');
    document.getElementById('gmNavOverlay').classList.add('open');
    document.body.classList.add('gm-nav-open', 'gm-drawer-open');
  }
  function close() {
    var d = document.getElementById('gmNav'); if (!d) return;
    d.classList.remove('open'); d.setAttribute('aria-hidden', 'true');
    document.getElementById('gmNavOverlay').classList.remove('open');
    document.body.classList.remove('gm-nav-open', 'gm-drawer-open');
  }
  window.openNavDrawer = open;
  window.closeNavDrawer = close;

  // Menu button next to the page's own back arrow (same header, no layout change elsewhere)
  function addButton() {
    if (document.querySelector('.gm-nav-btn') || page === 'index-ar.html') return;
    var header = document.querySelector('header') || document.body;
    // a page that already shows a (dead) "menu" icon: make that icon open the menu
    var icons = header.querySelectorAll('.material-symbols-outlined');
    for (var j = 0; j < icons.length; j++) {
      var ic = icons[j], host = ic.closest('button,a') || ic;
      if (ic.textContent.trim() === 'menu' && !host.getAttribute('onclick') && !host.getAttribute('href')) {
        host.classList.add('gm-nav-btn'); host.setAttribute('role', 'button'); host.setAttribute('aria-label', 'القائمة'); host.style.cursor = 'pointer';
        host.addEventListener('click', open); return;
      }
    }
    var SEL = '[onclick*="gmSmartBack"],[onclick*="history.back"],[onclick*="headerBack"],[onclick*="goBack"],[aria-label="رجوع"]';
    var back = header.querySelector(SEL) || document.querySelector(SEL);
    if (!back) {
      for (var i = 0; i < icons.length; i++) if (icons[i].textContent.trim() === 'arrow_forward') { back = icons[i].closest('button,a'); break; }
    }
    if (!back && header === document.body) return;
    var btn = document.createElement('button');
    btn.type = 'button'; btn.className = 'gm-nav-btn'; btn.setAttribute('aria-label', 'القائمة'); btn.title = 'القائمة';
    btn.innerHTML = '<span class="material-symbols-outlined">menu</span>';
    btn.addEventListener('click', open);
    if (back && back.parentNode) back.parentNode.insertBefore(btn, back.nextSibling);
    else header.firstElementChild ? header.firstElementChild.insertBefore(btn, header.firstElementChild.firstChild) : header.appendChild(btn);
  }

  // Hide links the signed-in staff member has no permission for
  async function applyPermissions() {
    try {
      if (typeof requireGoldMindSession !== 'function' || typeof goldmindClient === 'undefined') return;
      var key = 'gm_nav_perm_' + (typeof GOLDMIND_STAFF_ID !== 'undefined' ? GOLDMIND_STAFF_ID : '');
      var me = null;
      try { me = JSON.parse(sessionStorage.getItem(key) || 'null'); } catch (e) { /* ignore */ }
      if (!me) {
        if (typeof GOLDMIND_STAFF_ID === 'undefined' || !GOLDMIND_STAFF_ID) { await new Promise(function (r) { setTimeout(r, 1500); }); }
        if (typeof GOLDMIND_STAFF_ID === 'undefined' || !GOLDMIND_STAFF_ID) return;
        var res = await goldmindClient.from('staff').select('role, permissions').eq('id', GOLDMIND_STAFF_ID).maybeSingle();
        me = res && res.data; if (!me) return;
        key = 'gm_nav_perm_' + GOLDMIND_STAFF_ID;
        try { sessionStorage.setItem(key, JSON.stringify(me)); } catch (e) { /* ignore */ }
      }
      if (me.role === 'owner') return;
      var perms = me.permissions || {};
      document.querySelectorAll('[data-nav-perm]').forEach(function (a) { if (!a.getAttribute('data-nav-perm').split('|').some(function (k) { return perms[k]; })) a.style.display = 'none'; });
    } catch (e) { /* menu stays complete */ }
  }

  function mount() {
    build();
    addButton();
    setTimeout(applyPermissions, 600);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();
})();
