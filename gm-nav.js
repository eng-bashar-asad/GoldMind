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
      ['customer-add-ar.html', 'person_add', 'إضافة عميل', 'add_customers'],
      ['customer-debts-ar.html', 'groups', 'العملاء — الديون وكشف الحساب', 'view_customers'],
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
      ['expense-entry-ar.html', 'receipt', 'المصاريف', 'manage_daily_cashbox'],
      ['gifts-ar.html', 'redeem', 'إخراج هدايا', 'give_gifts'],
      ['main-cashbox-ar.html', 'account_balance', 'الصندوق الرئيسي', 'manage_daily_cashbox'],
      ['ledger-ar.html', 'handshake', 'حسابات التجار', 'view_traders'],
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
      ['theme-picker-ar.html', 'palette', 'مظهر التطبيق'],
      ['account-security-ar.html', 'lock', 'الأمان وكلمة المرور'],
      ['fiscal-year-close-ar.html', 'event_repeat', 'إغلاق السنة المالية', 'edit_settings'],
      ['subscription-ar.html', 'workspace_premium', 'الاشتراك', 'manage_subscription'],
      ['support-contact-ar.html', 'support_agent', 'تواصل مع الدعم'],
      ['#tz', 'schedule', 'المنطقة الزمنية للعرض'] ] }
  ];
  window.GM_NAV_GROUPS = GROUPS;

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
    @media (prefers-reduced-motion:reduce){#gmNav,#gmNav .gn-b,#gmNav .gn-chev{transition:none!important}}
  `;
  document.head.appendChild(css);

  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  function build() {
    var ov = document.createElement('div'); ov.id = 'gmNavOverlay';
    var d = document.createElement('aside'); d.id = 'gmNav'; d.setAttribute('aria-label', 'القائمة'); d.setAttribute('aria-hidden', 'true');
    var html = '<div class="gn-head"><b>GoldMind</b><button type="button" class="gn-x" aria-label="إغلاق القائمة"><span class="material-symbols-outlined">close</span></button></div><nav>';
    GROUPS.forEach(function (g) {
      var here = g.l.some(function (x) { return x[0] === page; });
      html += '<div class="gn-g' + (here ? ' open' : '') + '"><button type="button" class="gn-h" aria-expanded="' + here + '"><span class="material-symbols-outlined gn-ic">' + g.i + '</span><span>' + esc(g.t) + '</span><span class="material-symbols-outlined gn-chev">expand_more</span></button><div class="gn-b"><div>';
      g.l.forEach(function (x) {
        html += '<a class="gn-a' + (x[0] === page ? ' here' : '') + '" href="' + x[0] + '"' + (x[3] ? ' data-nav-perm="' + x[3] + '"' : '') + '><span class="material-symbols-outlined">' + x[1] + '</span><span>' + esc(x[2]) + '</span></a>';
      });
      html += '</div></div></div>';
    });
    html += '</nav><div class="gn-foot"><button type="button" class="gn-out"><span class="material-symbols-outlined">logout</span>تسجيل الخروج</button></div>';
    d.innerHTML = html;
    document.body.appendChild(ov); document.body.appendChild(d);

    ov.addEventListener('click', close);
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
      document.querySelectorAll('[data-nav-perm]').forEach(function (a) { if (!perms[a.getAttribute('data-nav-perm')]) a.style.display = 'none'; });
    } catch (e) { /* menu stays complete */ }
  }

  function mount() {
    build();
    addButton();
    setTimeout(applyPermissions, 600);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();
})();
