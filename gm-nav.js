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
      ['daily-cashbox-ar.html', 'point_of_sale', 'الحركة اليومية', 'manage_daily_cashbox'],
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
      ['staff-sales-ar.html', 'leaderboard', 'مبيعات الموظفين', 'view_profit_report'],
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
    /* menu look (Bashar 2026-11-02): dark, or light glass; chosen at the top of the menu, kept per device */
    #gmNav .gn-style{display:flex;gap:4px;margin:0 14px 8px;padding:4px;border-radius:14px;background:#2A251C}
    #gmNav .gn-style button{flex:1;min-height:38px;border:0;border-radius:10px;background:transparent;color:#BFB39A;font:inherit;font-size:13px;font-weight:700;display:flex;align-items:center;justify-content:center;gap:6px;cursor:pointer}
    #gmNav .gn-style button .material-symbols-outlined{font-size:18px}
    #gmNav .gn-style button[aria-checked="true"]{background:#D9B45A;color:#17140F}
    #gmNav .gn-search{display:flex;align-items:center;gap:8px;margin:0 14px 6px;min-height:44px;padding:0 12px;border-radius:14px;border:1px solid #3a3226;background:#2A251C;color:#BFB39A;font:inherit;font-size:13.5px;cursor:pointer;text-align:start;width:calc(100% - 28px)}
    #gmNav .gn-search .gn-st{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    #gmNav kbd,.gm-pal kbd{font:inherit;font-size:11px;border-radius:6px;padding:2px 6px;background:#3a3226;color:#E9CF8B;direction:ltr;white-space:nowrap}
    #gmNav .gn-sec{display:flex;align-items:center;justify-content:space-between;font-size:11.5px;font-weight:700;color:#8C8270;padding:8px 22px 2px}
    #gmNav .gn-sec button{border:0;background:transparent;color:#D9B45A;font:inherit;font-size:12px;font-weight:700;cursor:pointer;min-height:36px;padding:0 4px}
    #gmNav .gn-favempty{font-size:12px;color:#8C8270;padding:2px 24px 6px}
    #gmNav a.gn-a{position:relative}
    #gmNav .gn-badge{margin-inline-start:auto;min-width:22px;height:22px;padding:0 7px;border-radius:999px;font-size:11.5px;font-weight:700;display:inline-flex;align-items:center;justify-content:center;background:#2A251C;color:#E9CF8B;white-space:nowrap}
    #gmNav .gn-badge.red{background:#dc2626;color:#fff}
    #gmNav .gn-badge.amber{background:#f59e0b;color:#2a1a00}
    #gmNav .gn-badge.dot{min-width:9px;width:9px;height:9px;padding:0;background:#dc2626}
    #gmNav .gn-badge.txt{background:transparent;color:#BFB39A;font-weight:600;padding:0}
    #gmNav a.gn-a.here .gn-badge:not(.red):not(.amber):not(.dot){background:rgba(23,20,15,.15);color:#17140F}
    #gmNav .gn-star{margin-inline-start:6px;width:34px;height:34px;border:0;border-radius:8px;background:transparent;color:#8C8270;display:none;align-items:center;justify-content:center;cursor:pointer;flex:none}
    #gmNav.gn-editing .gn-star{display:inline-flex}
    #gmNav .gn-star.on{color:#E9CF8B}
    #gmNav .gn-me{display:flex;align-items:center;gap:10px;padding:8px;border-radius:14px;background:#2A251C;margin:0 0 6px}
    #gmNav .gn-av{width:38px;height:38px;border-radius:50%;background:#E9CF8B;color:#2A1F08;display:flex;align-items:center;justify-content:center;font-weight:700;position:relative;flex:none}
    #gmNav .gn-av::after{content:"";position:absolute;bottom:-1px;left:-1px;width:11px;height:11px;border-radius:50%;background:#16a34a;border:2px solid #2A251C}
    #gmNav .gn-me-t{min-width:0;flex:1;line-height:1.35}
    #gmNav .gn-me-t b{display:block;font-size:13.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    #gmNav .gn-me-t span{font-size:11.5px;opacity:.75;display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    #gmNav .gn-me a{font-size:12px;font-weight:700;color:#D9B45A;white-space:nowrap;text-decoration:underline;min-height:36px;display:inline-flex;align-items:center}
    #gmNav.gn-light{background:linear-gradient(160deg,rgba(255,250,238,.84),rgba(250,236,205,.74) 55%,rgba(226,187,112,.66));-webkit-backdrop-filter:blur(22px) saturate(160%);backdrop-filter:blur(22px) saturate(160%);color:#2E2618;border:1px solid rgba(255,255,255,.7)}
    @supports not ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))){#gmNav.gn-light{background:#FBF3E2}}
    #gmNav.gn-light .gn-head,#gmNav.gn-light .gn-foot{border-color:rgba(140,106,34,.22)}
    #gmNav.gn-light .gn-head b{color:#7A5A14}
    #gmNav.gn-light .gn-x,#gmNav.gn-light .gn-mini{background:rgba(255,255,255,.6);color:#3a301e}
    #gmNav.gn-light .gn-h{color:#2E2618}
    #gmNav.gn-light .gn-h .gn-ic,#gmNav.gn-light a.gn-a .material-symbols-outlined{color:#8c6a22}
    #gmNav.gn-light .gn-h .gn-chev{color:#8a7a58}
    #gmNav.gn-light a.gn-a{color:#3a301e}
    #gmNav.gn-light a.gn-a:hover{background:rgba(255,255,255,.45)}
    #gmNav.gn-light a.gn-a.here{background:rgba(255,255,255,.88);color:#1f1808;font-weight:700;box-shadow:0 4px 14px rgba(120,85,20,.18),inset 0 0 0 1px rgba(201,154,60,.55)}
    #gmNav.gn-light a.gn-a.here .material-symbols-outlined{color:#8c6a22}
    #gmNav.gn-light .gn-style,#gmNav.gn-light .gn-search,#gmNav.gn-light .gn-me{background:rgba(255,255,255,.58);border-color:rgba(255,255,255,.8);color:#5b4a2a}
    #gmNav.gn-light .gn-style button{color:#6b5a38}
    #gmNav.gn-light .gn-style button[aria-checked="true"]{background:#fff;color:#1f1808;box-shadow:0 2px 6px rgba(120,85,20,.22)}
    #gmNav.gn-light kbd{background:rgba(140,106,34,.14);color:#6b4f12}
    #gmNav.gn-light .gn-sec,#gmNav.gn-light .gn-favempty{color:#7a6a48}
    #gmNav.gn-light .gn-sec button,#gmNav.gn-light .gn-me a{color:#7A5A14}
    #gmNav.gn-light .gn-badge{background:rgba(140,106,34,.16);color:#5e4510}
    #gmNav.gn-light .gn-badge.txt{background:transparent;color:#6b4f12}
    #gmNav.gn-light .gn-out{color:#b42318}
    #gmNav.gn-light .gn-av::after{border-color:#fff}
    #gmNav.gn-light .gn-star{color:#a08c60}
    #gmNav.gn-light .gn-star.on{color:#c8901a}
    .gm-pal-ov{position:fixed;inset:0;z-index:10050;background:rgba(40,28,8,.32);-webkit-backdrop-filter:blur(4px);backdrop-filter:blur(4px);display:none;align-items:flex-start;justify-content:center;padding:10vh 12px 0}
    .gm-pal-ov.open{display:flex}
    .gm-pal{width:min(620px,100%);max-height:74vh;display:flex;flex-direction:column;border-radius:20px;overflow:hidden;background:rgba(255,250,240,.97);box-shadow:0 30px 80px rgba(60,40,8,.35);direction:rtl;color:#2E2618;font-family:inherit}
    .gm-pal-in{display:flex;align-items:center;gap:8px;padding:0 16px;border-bottom:1px solid #EADCBC}
    .gm-pal-in input{flex:1;min-width:0;border:0!important;background:transparent!important;font:inherit;font-size:17px;padding:16px 4px;outline:none;box-shadow:none!important;color:#2E2618}
    .gm-pal-in button{border:0;background:transparent;min-width:44px;min-height:44px;color:#7A5A14;font:inherit;font-weight:700;cursor:pointer}
    .gm-pal kbd{background:rgba(140,106,34,.14);color:#6b4f12}
    .gm-pal-list{overflow-y:auto;padding-bottom:8px}
    .gm-pal-g{font-size:11.5px;color:#8a7a58;padding:10px 18px 4px;font-weight:700}
    .gm-pal-row{display:flex;align-items:center;gap:12px;padding:10px 18px;min-height:44px;font-size:14px;color:inherit;text-decoration:none}
    .gm-pal-row .material-symbols-outlined{color:#8c6a22}
    .gm-pal-row small{margin-inline-start:auto;color:#8a7a58;font-size:12px}
    .gm-pal-row.on{background:#F3E6C6}
    .gm-pal-empty{padding:18px;text-align:center;color:#8a7a58;font-size:13px}
    @media (max-width:640px){.gm-pal-ov{padding:0}.gm-pal{max-height:100%;height:100%;border-radius:0}.gm-pal kbd{display:none}}
    @media (max-width:1023px){#gmNav .gn-search kbd{display:none}}
    @media screen and (min-width:1024px){
      /* flush with the screen edges so it meets the page's top bar (Bashar 2026-11-02: a floating panel didn't line up) */
      html.gm-desk #gmNav.gn-light{top:0;right:0;height:100%;border-radius:0;border-width:0 0 0 1px;border-color:rgba(140,106,34,.22);box-shadow:-10px 0 30px rgba(90,62,15,.10)}
      html.gm-desk.gm-navlight{--gm-side:288px}
      html.gm-desk.gm-navlight.gm-mini{--gm-side:100px}
      html.gm-desk.gm-mini #gmNav .gn-style,html.gm-desk.gm-mini #gmNav .gn-sec,html.gm-desk.gm-mini #gmNav .gn-favempty,html.gm-desk.gm-mini #gmNav .gn-search .gn-st,html.gm-desk.gm-mini #gmNav .gn-search kbd,html.gm-desk.gm-mini #gmNav .gn-me-t,html.gm-desk.gm-mini #gmNav .gn-me a{display:none}
      html.gm-desk.gm-mini #gmNav .gn-search{justify-content:center;padding:0;margin:0 10px 6px;width:calc(100% - 20px)}
      html.gm-desk.gm-mini #gmNav .gn-me{justify-content:center;background:transparent}
      html.gm-desk.gm-mini #gmNav a.gn-a>.gn-badge{display:inline-flex!important;position:absolute;top:2px;left:6px;min-width:16px;height:16px;font-size:9.5px;padding:0 4px}
      html.gm-desk.gm-mini #gmNav a.gn-a>.gn-badge.txt{display:none!important}
    }
    /* ---- glass pages (Bashar 2026-11-02): translucent cards over the GoldMind emblem, light themes only, screen only ---- */
    #gmNav .gn-pages{display:flex;align-items:center;gap:6px;margin:-2px 14px 8px;font-size:11.5px;font-weight:700;color:#8C8270}
    #gmNav .gn-pages .gn-style{flex:1;margin:0;padding:3px}
    #gmNav .gn-pages .gn-style button{min-height:32px;font-size:12px}
    #gmNav.gn-light .gn-pages{color:#7a6a48}
    #gmGlassBg{display:none}
    @media screen{
      html.gm-glass.gm-light-canvas{background:radial-gradient(900px 640px at 88% 4%,rgba(212,175,55,.16) 0,transparent 60%),radial-gradient(800px 600px at 4% 98%,rgba(184,134,43,.12) 0,transparent 58%),var(--gm-bg,#F7F1E3)!important}
      html.gm-glass.gm-light-canvas body{background:transparent!important}
      html.gm-glass.gm-light-canvas #gmGlassBg{display:block;position:fixed;inset:0;z-index:-1;pointer-events:none;overflow:hidden}
      html.gm-glass.gm-light-canvas{--gm-surface-lowest:rgba(255,252,244,.78)!important;--gm-surface-low:rgba(250,238,212,.72)!important}
      html.gm-glass.gm-light-canvas :is(.bg-surface-container-lowest,.bg-surface-container-low,.bg-white,.bg-surface):is(.rounded-lg,.rounded-xl,.rounded-2xl,.rounded-3xl,[class*="rounded-["]):not(.fixed *):not(input,select,textarea),
      html.gm-glass.gm-light-canvas :is(header.sticky,header.fixed,.sticky.top-0){-webkit-backdrop-filter:blur(14px) saturate(165%);backdrop-filter:blur(14px) saturate(165%)}
      html.gm-glass.gm-light-canvas .bg-white:is(.rounded-lg,.rounded-xl,.rounded-2xl,.rounded-3xl,[class*="rounded-["]):not(.fixed *):not(input,select,textarea){background-color:rgba(255,253,247,.78)!important}
      html.gm-glass.gm-light-canvas :is(.bg-surface-container-lowest,.bg-white):is(.rounded-xl,.rounded-2xl,.rounded-3xl,[class*="rounded-["]):not(.fixed *){border-color:rgba(255,255,255,.7)!important;box-shadow:0 14px 34px rgba(110,78,20,.10),inset 0 1px 0 rgba(255,255,255,.85)}
      /* page-made white cards (their own class names) */
      html.gm-glass.gm-light-canvas :is(.gm-row,.gm-mcard,.gm-qa,.gm-spec,.gd-card,.ss-card,.ss-kpi,.mc-card,.mc-kpi,.rp-card,.pc-card,.ld-card,.inv-card,.tax-card,.stc,.dsk-card,.dsk-kpi):not(.fixed *){background:rgba(255,253,247,.78)!important;-webkit-backdrop-filter:blur(14px) saturate(165%);backdrop-filter:blur(14px) saturate(165%);border:1px solid rgba(255,255,255,.7)!important;box-shadow:0 14px 34px rgba(110,78,20,.10),inset 0 1px 0 rgba(255,255,255,.85)}
      /* home (computer): its own surface colour + panels; quick-access tiles (phone + computer); stock status buttons; small chip buttons */
      html.gm-glass.gm-light-canvas .dsk-app{--dsk-surface:rgba(255,252,244,.78)!important;--dsk-surface-sunken:rgba(250,238,212,.7)!important;--dsk-bg:transparent!important;background:transparent!important}
      html.gm-glass.gm-light-canvas :is(.dsk-stat,.dsk-panel,.dsk-action-strip,.dsk-topbar):not(.fixed *){-webkit-backdrop-filter:blur(14px) saturate(165%);backdrop-filter:blur(14px) saturate(165%);border-color:rgba(255,255,255,.7)!important}
      html.gm-glass.gm-light-canvas :is(.gm-qg,.gm-status button:not([aria-pressed="true"]),.gm-chip-btn:not([style*="background"]),.dsk-customize-btn):not(.fixed *){background:rgba(255,253,247,.76)!important;-webkit-backdrop-filter:blur(12px) saturate(160%);backdrop-filter:blur(12px) saturate(160%);border-color:rgba(255,255,255,.72)!important;box-shadow:0 10px 26px rgba(110,78,20,.10),inset 0 1px 0 rgba(255,255,255,.85)}
      html.gm-glass.gm-light-canvas :is(input,select,textarea){background-color:rgba(255,255,255,.88)}
      html.gm-glass.gm-light-canvas .fixed :is(.bg-surface-container-lowest,.bg-surface-container-low,.bg-white,.bg-surface){background-color:#FFFDF8!important}
      html.gm-glass.gm-light-canvas .gm-bottom-tabs{background:rgba(255,252,244,.62)!important;-webkit-backdrop-filter:blur(16px) saturate(170%);backdrop-filter:blur(16px) saturate(170%);border-top-color:rgba(255,255,255,.7)}
      @supports not ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))){
        html.gm-glass.gm-light-canvas{--gm-surface-lowest:rgba(255,252,244,.9)!important;--gm-surface-low:rgba(250,238,212,.9)!important}
      }
      #gmGlassBg svg{position:absolute}
      #gmGlassBg .gmr{stroke-dasharray:640;stroke-dashoffset:640;animation:gmDraw 2.2s cubic-bezier(.22,1,.36,1) .2s forwards}
      #gmGlassBg .gms{transform-origin:100px 100px;animation:gmSpin 60s linear infinite}
      #gmGlassBg .gmc{transform-box:fill-box;transform-origin:bottom;animation:gmBreathe 5s ease-in-out infinite alternate}
      #gmGlassBg .gmc:nth-child(2){animation-delay:-1.2s}#gmGlassBg .gmc:nth-child(3){animation-delay:-2.4s}#gmGlassBg .gmc:nth-child(4){animation-delay:-3.6s}
      #gmGlassBg .gmt{transform-box:fill-box;transform-origin:center;animation:gmTwinkle 2.6s ease-in-out infinite}
      #gmGlassBg .gmt:nth-of-type(2){animation-delay:-.9s}#gmGlassBg .gmt:nth-of-type(3){animation-delay:-1.7s}
      @keyframes gmDraw{to{stroke-dashoffset:0}}
      @keyframes gmSpin{to{transform:rotate(360deg)}}
      @keyframes gmBreathe{from{transform:scaleY(.86)}to{transform:scaleY(1.06)}}
      @keyframes gmTwinkle{0%,100%{opacity:.25;transform:scale(.6)}50%{opacity:1;transform:scale(1.15)}}
      /* entrance: page blocks rise one after another, icons on buttons pop in; once per page load */
      @keyframes gmRise{from{opacity:0;transform:translateY(14px) scale(.985)}to{opacity:1;transform:none}}
      @keyframes gmPop{from{opacity:0;transform:scale(.55)}to{opacity:1;transform:none}}
      /* backwards, not both: a transform kept after the animation turns the block into the frame of any fixed
         pop-up inside it, so edit sheets opened at the bottom of the page instead of on screen */
      html.gm-anim main > :nth-child(-n+14){animation:gmRise .5s cubic-bezier(.22,1,.36,1) backwards}
      html.gm-anim main > :nth-child(2){animation-delay:55ms}html.gm-anim main > :nth-child(3){animation-delay:110ms}html.gm-anim main > :nth-child(4){animation-delay:165ms}
      html.gm-anim main > :nth-child(5){animation-delay:220ms}html.gm-anim main > :nth-child(6){animation-delay:275ms}html.gm-anim main > :nth-child(7){animation-delay:330ms}
      html.gm-anim main > :nth-child(8){animation-delay:385ms}html.gm-anim main > :nth-child(n+9){animation-delay:440ms}
      html.gm-anim .gm-pop{animation:gmPop .42s cubic-bezier(.34,1.56,.64,1) backwards;animation-delay:calc(var(--gm-i,0) * 45ms + 180ms)}
      @media (hover:hover){html.gm-glass.gm-light-canvas main :is(a,button):is(.rounded-xl,.rounded-2xl):not(:disabled){transition:transform .22s cubic-bezier(.22,1,.36,1),box-shadow .22s}
        html.gm-glass.gm-light-canvas main :is(a,button):is(.rounded-xl,.rounded-2xl):not(:disabled):hover{transform:translateY(-3px);box-shadow:0 18px 40px rgba(110,78,20,.18)}}
      html.gm-noblur *{-webkit-backdrop-filter:none!important;backdrop-filter:none!important}
      html.gm-noblur #gmGlassBg *{animation:none!important;stroke-dashoffset:0!important}
      @media (prefers-reduced-motion:reduce){html.gm-anim main > *,html.gm-anim .gm-pop{animation:none!important}#gmGlassBg *{animation:none!important;stroke-dashoffset:0!important}}
    }
    @media print{#gmNav,#gmNavOverlay,.gm-nav-btn,.gm-pal-ov,#gmGlassBg{display:none!important}}
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
    /* notifications instead of alert() boxes (idea from 21st.dev toasts) */
    #gmToasts{position:fixed;z-index:10050;top:calc(12px + env(safe-area-inset-top));inset-inline:0;margin:0 auto;width:min(440px,calc(100vw - 24px));display:flex;flex-direction:column;gap:8px;pointer-events:none;direction:rtl}
    @media screen and (min-width:1024px){#gmToasts{top:auto;bottom:24px;inset-inline-end:24px;inset-inline-start:auto;margin:0}}
    .gm-toast{pointer-events:auto;display:flex;align-items:flex-start;gap:10px;background:#1C1A16;color:#FBF8F1;border-radius:14px;padding:12px 12px 12px 14px;box-shadow:0 12px 32px -8px rgba(0,0,0,.45);font-size:13.5px;line-height:1.55;border-inline-start:4px solid #D9B45A;animation:gmToastIn .28s cubic-bezier(.22,1,.36,1) both}
    .gm-toast.err{border-inline-start-color:#E5533D}.gm-toast.ok{border-inline-start-color:#3FA35B}
    .gm-toast .material-symbols-outlined{font-size:20px;flex:none;margin-top:1px}
    .gm-toast.err .material-symbols-outlined{color:#F08A78}.gm-toast.ok .material-symbols-outlined{color:#7BD08F}.gm-toast.info .material-symbols-outlined{color:#E9CF8B}
    .gm-toast p{margin:0;flex:1;white-space:pre-line;word-break:break-word}
    .gm-toast button{flex:none;width:28px;height:28px;border:0;border-radius:8px;background:rgba(255,255,255,.08);color:#E6DECB;display:flex;align-items:center;justify-content:center;cursor:pointer}
    .gm-toast.out{animation:gmToastOut .22s ease-in both}
    @keyframes gmToastIn{from{opacity:0;transform:translateY(-10px) scale(.98)}to{opacity:1;transform:none}}
    @keyframes gmToastOut{to{opacity:0;transform:translateY(-6px)}}
    @media (prefers-reduced-motion:reduce){.gm-toast,.gm-toast.out{animation:none}}
    /* empty lists: a small drawing above the message (idea from 21st.dev empty states) */
    .gm-empty{display:flex!important;flex-direction:column;align-items:center;justify-content:center;gap:10px;padding:28px 12px!important;text-align:center;color:var(--gm-on-surface-variant,#6B6355)}
    td.gm-empty{display:table-cell!important}
    .gm-empty.hidden{display:none!important}
    /* «البائع» picker on sale screens (gmSellerPicker) */
    .gm-seller{display:flex;align-items:center;gap:8px;min-height:44px;padding:0 6px 0 10px;border:1px solid #CBBF9E;border-radius:12px;background:#FFFDF8;font-size:13px;font-weight:700;color:#211D17}
    .gm-seller .material-symbols-outlined{font-size:19px;color:#7A6640}
    .gm-seller select{flex:1;min-width:0;height:40px;border:0;background:transparent;font:inherit;font-weight:600;color:inherit;box-shadow:none}
    .gm-seller.gm-seller-other{border-color:#D9731A;background:#FDF0DC}
    /* date / time pickers: on a right-to-left page Android draws the day / month / year parts on top of each other
       (17/10 shows as a blur); they are always laid out left to right, the text still sits on the right */
    input[type=date],input[type=datetime-local],input[type=time],input[type=month],input[type=week]{direction:ltr;text-align:right;unicode-bidi:isolate}
    input.gm-date-masked{color:transparent!important;-webkit-text-fill-color:transparent}
    input.gm-date-masked::-webkit-datetime-edit,input.gm-date-masked::-webkit-date-and-time-value{opacity:0}
    input[type=date]::-webkit-datetime-edit,input[type=datetime-local]::-webkit-datetime-edit,input[type=time]::-webkit-datetime-edit,input[type=month]::-webkit-datetime-edit{direction:ltr}
    .gm-empty::before{content:'';width:72px;height:60px;flex:none;display:block;margin:0 auto 10px;background:no-repeat center/contain url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 72 60' fill='none'%3E%3Cellipse cx='36' cy='54' rx='24' ry='4' fill='%23E4DAC0'/%3E%3Crect x='14' y='18' width='44' height='30' rx='6' fill='%23FBF8F1' stroke='%23C9B98F' stroke-width='2'/%3E%3Cpath d='M14 26h44' stroke='%23C9B98F' stroke-width='2'/%3E%3Cpath d='M26 36h20M30 41h12' stroke='%23D9C79C' stroke-width='2' stroke-linecap='round'/%3E%3Cpath d='M22 18l5-9h18l5 9' stroke='%23C9B98F' stroke-width='2' stroke-linejoin='round'/%3E%3Ccircle cx='58' cy='10' r='3' fill='%23D9B45A'/%3E%3Cpath d='M10 9v6M7 12h6' stroke='%23D9B45A' stroke-width='2' stroke-linecap='round'/%3E%3C/svg%3E")}
    /* press feel: buttons sink a little when pressed */
    .gm-qg,.dsk-action,.gm-tab,.gm-tab-sale,.gm-fab,.cd-act,.cu-act,.ns-pb-btn,#save-invoice-btn,#save-btn,.gm-cta,.gm-chip-btn,.gm-hbtn,.qa-tile{transition:transform .12s ease,filter .12s ease}
    .gm-qg:active,.dsk-action:active,.gm-tab:active,.gm-tab-sale:active,.gm-fab:active,.cd-act:active,.cu-act:active,.ns-pb-btn:active,#save-invoice-btn:active,#save-btn:active,.gm-cta:active,.gm-chip-btn:active,.gm-hbtn:active{transform:scale(.96)!important;filter:brightness(.97)}
    .gm-qg:active .gm-gi,.dsk-action:active .gm-gi{transform:translateY(2px);box-shadow:0 0 0 1px color-mix(in srgb,var(--c,#C8952E) 55%,transparent) inset,0 -6px 10px color-mix(in srgb,var(--c,#C8952E) 22%,transparent) inset,0 4px 8px -6px rgba(0,0,0,.6)!important}
    /* a button busy saving shows a spinner (its text already says «جارِ …») */
    button.gm-busy{position:relative;opacity:.85;cursor:progress}
    button.gm-busy:not([data-total])::after{content:'';display:inline-block;width:15px;height:15px;margin-inline-start:8px;vertical-align:-3px;border-radius:50%;border:2px solid currentColor;border-top-color:transparent;animation:gmSpin .7s linear infinite}
    @keyframes gmSpin{to{transform:rotate(360deg)}}
    /* phone: swipe from the edge to go back, pull down to refresh */
    #gmEdgeBack,#gmPull{position:fixed;z-index:10040;pointer-events:none;display:flex;align-items:center;justify-content:center;width:44px;height:44px;border-radius:50%;background:#1C1A16;color:#E9CF8B;box-shadow:0 8px 20px rgba(0,0,0,.3);opacity:0;transition:opacity .15s}
    #gmEdgeBack{top:50%;right:6px;margin-top:-22px}
    #gmPull{top:10px;left:50%;margin-left:-22px}
    #gmEdgeBack.on,#gmPull.on{opacity:1}
    #gmPull.go .material-symbols-outlined{animation:gmSpin .7s linear infinite}
    @media (prefers-reduced-motion:reduce){.gm-qg,.dsk-action,.gm-tab,.gm-tab-sale{transition:none}button.gm-busy:not([data-total])::after,#gmPull.go .material-symbols-outlined{animation:none}}
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

  // ---- notifications (replace the blocking alert() boxes) ----
  // kind: 'err' | 'ok' | 'info'. A message still on screen when the page changes is shown again on the next page.
  var TOAST_KEY = 'gm_toasts_carry';
  function toastBox() {
    var b = document.getElementById('gmToasts');
    if (!b) { b = document.createElement('div'); b.id = 'gmToasts'; b.setAttribute('aria-live', 'polite'); (document.body || document.documentElement).appendChild(b); }
    return b;
  }
  function kindOf(t) {
    if (/تعذّر|تعذر|خطأ|فشل|لا يمكن|ليس لديك|الرجاء|فضلاً|غير صحيح|غير كاف|مطلوب|انتهت|لا يوجد|لا توجد|لم ت|error/i.test(t)) return 'err';
    if (/تم |تمت |نجاح|حُفظ|حفظت|بنجاح/.test(t)) return 'ok';
    return 'info';
  }
  window.gmNotify = function (text, kind, ms) {
    text = String(text == null ? '' : text); if (!text) return;
    kind = kind || kindOf(text);
    var el = document.createElement('div');
    el.className = 'gm-toast ' + kind; el.setAttribute('role', kind === 'err' ? 'alert' : 'status');
    el.innerHTML = '<span class="material-symbols-outlined" aria-hidden="true">' + (kind === 'err' ? 'error' : kind === 'ok' ? 'check_circle' : 'info') + '</span><p></p><button type="button" aria-label="إغلاق"><span class="material-symbols-outlined" style="font-size:17px;margin:0">close</span></button>';
    el.querySelector('p').textContent = text;
    el._gmText = text; el._gmKind = kind;
    var box = toastBox(); box.appendChild(el);
    while (box.children.length > 4) box.firstChild.remove();
    var close = function () { if (!el.isConnected) return; el.classList.add('out'); setTimeout(function () { el.remove(); }, 220); };
    el.querySelector('button').onclick = close;
    setTimeout(close, ms || (kind === 'err' ? 8000 : 4500));
    return el;
  };
  window.addEventListener('pagehide', function () {
    var b = document.getElementById('gmToasts'); if (!b || !b.children.length) return;
    try { sessionStorage.setItem(TOAST_KEY, JSON.stringify(Array.prototype.map.call(b.children, function (t) { return [t._gmText, t._gmKind]; }))); } catch (e) {}
  });
  function carryToasts() {
    var list = null;
    try { list = JSON.parse(sessionStorage.getItem(TOAST_KEY) || 'null'); sessionStorage.removeItem(TOAST_KEY); } catch (e) {}
    (list || []).forEach(function (x) { window.gmNotify(x[0], x[1]); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', carryToasts); else carryToasts();
  // alert() keeps its words but no longer blocks the page; confirm() stays a real question
  if (!window.__gmNativeAlert) { window.__gmNativeAlert = window.alert; window.alert = function (m) { window.gmNotify(m); }; }

  // ---- a tiny vibration on the main buttons (Android; iPhone has no web vibration) ----
  document.addEventListener('pointerdown', function (e) {
    if (e.pointerType !== 'touch' || !navigator.vibrate) return;
    if (e.target.closest && e.target.closest('.gm-qg, .gm-tab-sale, .gm-fab, .ns-pb-btn, #save-invoice-btn, #save-btn, .cd-act, .cu-act')) { try { navigator.vibrate(8); } catch (x) {} }
  }, { passive: true });

  // ---- phone gestures ----
  var phone = function () { return window.matchMedia && matchMedia('(max-width: 1023px)').matches; };
  function bubble(id, icon) {
    var b = document.getElementById(id);
    if (!b) { b = document.createElement('div'); b.id = id; b.setAttribute('aria-hidden', 'true'); b.innerHTML = '<span class="material-symbols-outlined">' + icon + '</span>'; document.body.appendChild(b); }
    return b;
  }
  var busyUi = function () { return document.querySelector('.ns-shade.ns-open, #mobActionStrip.gm-arrange, .gm-qg-ghost, #gmNav[aria-hidden="false"], [role="dialog"]:not(.hidden)'); };
  // swipe in from the right edge (the start side in Arabic) → back
  var eb = null;
  document.addEventListener('touchstart', function (e) {
    if (!phone() || e.touches.length !== 1 || page === 'index-ar.html' || busyUi()) return;
    var t = e.touches[0];
    if (t.clientX > window.innerWidth - 22) eb = { x: t.clientX, y: t.clientY, dx: 0 };
  }, { passive: true });
  document.addEventListener('touchmove', function (e) {
    if (!eb) return;
    var t = e.touches[0]; eb.dx = eb.x - t.clientX;
    if (Math.abs(t.clientY - eb.y) > 60) { eb = null; bubble('gmEdgeBack', 'arrow_forward').classList.remove('on'); return; }
    var b = bubble('gmEdgeBack', 'arrow_forward');
    b.classList.toggle('on', eb.dx > 24);
    b.style.transform = 'translateX(' + (-Math.min(eb.dx, 90) / 2) + 'px) scale(' + (eb.dx > 80 ? 1.1 : 1) + ')';
  }, { passive: true });
  document.addEventListener('touchend', function () {
    if (!eb) return;
    var go = eb.dx > 80; eb = null;
    var b = document.getElementById('gmEdgeBack'); if (b) b.classList.remove('on');
    if (!go) return;
    // the page's own back button knows where "back" is; otherwise the shared back
    var own = document.querySelector('header [onclick*="gmSmartBack"], header [onclick*="goBack"], header [aria-label="رجوع"], [onclick*="gmSmartBack"]');
    if (own) own.click(); else if (typeof window.gmSmartBack === 'function') window.gmSmartBack('index-ar.html'); else history.back();
  });
  // pull down at the top of a list page → refresh (only on pages that just show data)
  var PULL_PAGES = ['index-ar.html', 'invoices-list-ar.html', 'customers-ar.html', 'inventory-list-ar.html', 'customer-debts-ar.html', 'reports-ar.html', 'ledger-ar.html', 'daily-cashbox-ar.html', 'branch-transfers-ar.html', 'repairs-ar.html'];
  var pl = null;
  document.addEventListener('touchstart', function (e) {
    if (!phone() || e.touches.length !== 1 || PULL_PAGES.indexOf(page) < 0 || window.scrollY > 0 || busyUi()) return;
    if (e.target.closest('input, textarea, select, #mobActionStrip, [contenteditable], .overflow-x-auto, .rp-chart')) return;
    pl = { y: e.touches[0].clientY, dy: 0 };
  }, { passive: true });
  document.addEventListener('touchmove', function (e) {
    if (!pl) return;
    pl.dy = e.touches[0].clientY - pl.y;
    if (pl.dy < 0 || window.scrollY > 0) { pl.dy = 0; bubble('gmPull', 'refresh').classList.remove('on'); return; }
    var b = bubble('gmPull', 'refresh');
    b.classList.toggle('on', pl.dy > 20);
    b.style.transform = 'translateY(' + Math.min(pl.dy * .5, 60) + 'px) rotate(' + Math.min(pl.dy * 2, 300) + 'deg)';
  }, { passive: true });
  document.addEventListener('touchend', function () {
    if (!pl) return;
    var go = pl.dy > 110; pl = null;
    var b = document.getElementById('gmPull'); if (!b) return;
    if (go) { b.classList.add('go'); b.style.transform = 'translateY(50px)'; setTimeout(function () { location.reload(); }, 150); }
    else b.classList.remove('on');
  });

  // ---- empty lists get a small drawing ----
  var EMPTY_RE = /^(لا توجد|لا يوجد|لم تُضف|لم يتم|لا شيء)/;
  function markBusy() {
    document.querySelectorAll('button').forEach(function (b) {
      var busy = /^\s*جار[ِ]?\s/.test(b.textContent || '') && !b.querySelector('.animate-spin');
      if (busy !== b.classList.contains('gm-busy')) b.classList.toggle('gm-busy', busy);
    });
  }
  function markEmpty(root) {
    (root.querySelectorAll ? root : document).querySelectorAll('p, div, td, li').forEach(function (el) {
      if (el.classList.contains('gm-empty') || el.children.length || el.closest('#gmToasts, select, .gm-toast, button, a, label')) return;
      var t = (el.textContent || '').trim();
      if (t.length && t.length < 90 && EMPTY_RE.test(t) && /text-center|py-8|py-6|py-4|dsk-empty/.test(el.className)) el.classList.add('gm-empty');
    });
  }
  var emptyTimer = null;
  // Phones: Android draws a date box's value twice (two layers slightly apart) on a right-to-left page,
  // so the numbers land on top of each other. On touch screens the native text is hidden and the
  // date is written once on top, as DD/MM/YYYY; tapping still opens the phone's date picker.
  var COARSE = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
  var VALUE = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
  function dateText(v) { var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v || ''); return m ? m[3] + '/' + m[2] + '/' + m[1] : ''; }
  function maskDate(inp) {
    if (inp.__gmMask || !inp.parentNode) return;
    inp.__gmMask = true;
    var cs = getComputedStyle(inp);
    var wrap = document.createElement('span');
    wrap.className = 'gm-date-wrap';
    var full = /\b(w-full|flex-1)\b/.test(inp.className) || inp.style.width === '100%' || cs.display === 'block';
    wrap.style.cssText = 'position:relative;vertical-align:top;min-width:0;' + (full ? 'display:block;width:100%;' : 'display:inline-block;')
      + (/\bflex-1\b/.test(inp.className) ? 'flex:1 1 0%;' : '');
    var txt = document.createElement('span');
    txt.className = 'gm-date-txt';
    txt.setAttribute('aria-hidden', 'true');
    txt.style.cssText = 'position:absolute;inset:0;display:flex;align-items:center;pointer-events:none;direction:ltr;justify-content:flex-end;'
      + 'padding:0 ' + cs.paddingRight + ' 0 ' + cs.paddingLeft + ';font:inherit;font-size:' + cs.fontSize + ';color:' + cs.color + ';white-space:nowrap;overflow:hidden';
    inp.parentNode.insertBefore(wrap, inp);
    wrap.appendChild(inp); wrap.appendChild(txt);
    if (full) inp.style.width = '100%';
    inp.classList.add('gm-date-masked');
    var paint = function () { txt.textContent = dateText(VALUE.get.call(inp)); };
    // values set by the page's own code (inp.value = ...) repaint too
    Object.defineProperty(inp, 'value', { configurable: true, get: function () { return VALUE.get.call(inp); }, set: function (v) { VALUE.set.call(inp, v); paint(); } });
    inp.addEventListener('input', paint); inp.addEventListener('change', paint);
    paint();
  }
  function maskDates() { if (COARSE) document.querySelectorAll('input[type=date]:not(.gm-date-masked)').forEach(maskDate); }
  window.gmDateText = dateText;
  function watchEmpty() {
    markEmpty(document);
    maskDates();
    var busyQueued = false;
    new MutationObserver(function () {
      if (!busyQueued) { busyQueued = true; requestAnimationFrame(function () { busyQueued = false; markBusy(); }); }
      clearTimeout(emptyTimer); emptyTimer = setTimeout(function () { markEmpty(document); maskDates(); }, 60); })
      .observe(document.body, { childList: true, subtree: true, characterData: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', watchEmpty); else watchEmpty();

  // ---- Enter moves to the next field (every screen) ----
  // Enter: next visible, enabled field in the same form / dialog / section; on the last field it
  // presses the form's save button. Shift+Enter: back one field. Left alone: barcode/search boxes,
  // fields with their own Enter (inline onkeydown, or a handler that called preventDefault),
  // textareas, and anything inside [data-gm-enter="off"].
  var ENTER_SKIP = /barcode|باركود|search|بحث|scan|مسح/i;
  var SAVE_RE = /^(حفظ|ترحيل|تسجيل|إضافة|أضف|تأكيد|إصدار|إنشاء)/;
  function gmFields(scope) {
    return Array.prototype.filter.call(scope.querySelectorAll('input, select, textarea'), function (el) {
      if (el.disabled || el.readOnly || el.tabIndex < 0) return false;
      if (/^(hidden|button|submit|reset|file|checkbox|radio|range|color|image)$/i.test(el.type || '')) return false;
      if (el.closest('[data-gm-enter="off"], [hidden], .hidden')) return false;
      return !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
    });
  }
  function gmEnterScope(el) {
    return el.closest('form, [role=dialog], dialog, [data-gm-opdate], [data-enter-scope]')
      || el.closest('section, .gm-card, main') || document.body;
  }
  function gmSaveButton(scope) {
    var bs = Array.prototype.filter.call(scope.querySelectorAll('button, [type=submit]'), function (b) {
      return !b.disabled && (b.offsetWidth || b.offsetHeight) && !b.closest('[data-gm-enter="off"]');
    });
    return bs.find(function (b) { return b.type === 'submit' || b.hasAttribute('data-gm-save'); })
      || bs.find(function (b) { return SAVE_RE.test((b.textContent || '').trim()); });
  }
  window.gmEnterNext = function (el, back) {
    var scope = gmEnterScope(el), list = gmFields(scope), i = list.indexOf(el);
    if (i < 0) return false;
    var next = list[i + (back ? -1 : 1)];
    if (next) {
      next.focus();
      if (next.select && /^(text|number|tel|email|search|url|password|)$/i.test(next.type || '')) { try { next.select(); } catch (x) { /* number inputs */ } }
      return true;
    }
    if (back) return false;
    if (el.form) return false; // a real form: the browser's own Enter submits it
    var save = gmSaveButton(scope);
    if (save) { save.click(); return true; }
    return false;
  };
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' || e.defaultPrevented || e.isComposing || e.ctrlKey || e.metaKey || e.altKey) return;
    var t = e.target;
    if (!t || !t.matches || !t.matches('input, select') || !document.contains(t)) return;
    if (/^(button|submit|reset|file|checkbox|radio)$/i.test(t.type || '')) return;
    if (t.hasAttribute('onkeydown') || t.closest('[data-gm-enter="off"]')) return;
    if (ENTER_SKIP.test((t.id || '') + ' ' + (t.name || '') + ' ' + (t.placeholder || '') + ' ' + (t.getAttribute('aria-label') || ''))) return;
    if (t.getAttribute('list') && !t.value) return; // let the suggestion list open
    if (gmEnterNext(t, e.shiftKey)) e.preventDefault();
  });

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

  // ---- Menu extras (Bashar 2026-11-02): light/dark look, favourites, search (Ctrl+K), badges, who/branch card ----
  var STYLE_KEY = 'gm_nav_style', FAV_KEY = 'gm_nav_favs';
  var FAV_DEFAULT = ['new-sale-ar.html', 'daily-cashbox-ar.html', 'inventory-list-ar.html'];
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private mode */ } }
  function isDesk() { return !!(window.matchMedia && matchMedia('(min-width:1024px)').matches); }
  // default: light glass on computers, dark on phones and scanners (blur is heavy there)
  function navStyle() { var v = lsGet(STYLE_KEY); return v === 'light' || v === 'dark' ? v : (isDesk() ? 'light' : 'dark'); }
  function applyStyle(st) {
    var d = document.getElementById('gmNav'); if (!d) return;
    d.classList.toggle('gn-light', st === 'light');
    document.documentElement.classList.toggle('gm-navlight', st === 'light');
    d.querySelectorAll('.gn-style button[data-st]').forEach(function (b) { b.setAttribute('aria-checked', String(b.dataset.st === st)); });
  }
  function linkDef(href) {
    for (var i = 0; i < GROUPS.length; i++) for (var j = 0; j < GROUPS[i].l.length; j++) if (GROUPS[i].l[j][0] === href) return GROUPS[i].l[j];
    return null;
  }
  function favs() { try { var f = JSON.parse(lsGet(FAV_KEY) || 'null'); if (Array.isArray(f)) return f; } catch (e) { /* ignore */ } return FAV_DEFAULT.slice(); }
  function linkHtml(x, fav) {
    return '<a class="gn-a' + (fav ? ' gn-fav' : '') + (x[0] === page ? ' here' : '') + '" href="' + x[0] + '"' + (x[3] ? ' data-nav-perm="' + x[3] + '"' : '') + '><span class="material-symbols-outlined">' + x[1] + '</span><span>' + esc(x[2]) + '</span>'
      + (x[0] === '#tz' ? '' : '<button type="button" class="gn-star" data-href="' + x[0] + '" aria-label="إضافة إلى المفضّلة أو إزالتها"><span class="material-symbols-outlined">star</span></button>') + '</a>';
  }
  function renderFavs() {
    var d = document.getElementById('gmNav'); if (!d) return;
    var list = favs().map(linkDef).filter(Boolean);
    d.querySelector('.gn-favlist').innerHTML = list.length ? list.map(function (x) { return linkHtml(x, true); }).join('')
      : '<div class="gn-favempty">اضغط «تعديل» ثم النجمة بجانب أي صفحة لتثبيتها هنا.</div>';
    var f = favs();
    d.querySelectorAll('.gn-star').forEach(function (b) {
      var on = f.indexOf(b.dataset.href) !== -1;
      b.classList.toggle('on', on);
      b.firstChild.style.fontVariationSettings = on ? "'FILL' 1" : "'FILL' 0";
    });
    d.querySelectorAll('.gn-favlist a.gn-a').forEach(function (a) { a.title = (a.children[1] || a).textContent.trim(); });
    paintBadges();
    applyPermissions();
  }
  function toggleFav(href) {
    var f = favs(), i = f.indexOf(href);
    if (i === -1) f.push(href); else f.splice(i, 1);
    lsSet(FAV_KEY, JSON.stringify(f));
    renderFavs();
  }

  // Badges: small counts beside pages that need attention. Cached for 2 minutes per tab.
  var badges = {};
  function setBadge(href, html) { badges[href] = html; }
  function paintBadges() {
    var d = document.getElementById('gmNav'); if (!d) return;
    d.querySelectorAll('a.gn-a > .gn-badge').forEach(function (b) { b.remove(); });
    Object.keys(badges).forEach(function (href) {
      if (!badges[href]) return;
      d.querySelectorAll('a.gn-a[href="' + href + '"]').forEach(function (a) {
        var t = document.createElement('span'); t.innerHTML = badges[href];
        var b = t.firstChild; var star = a.querySelector('.gn-star');
        a.insertBefore(b, star || null);
      });
    });
  }
  async function storeReady() {
    for (var i = 0; i < 20 && (typeof GOLDMIND_STORE_ID === 'undefined' || !GOLDMIND_STORE_ID); i++) await new Promise(function (r) { setTimeout(r, 300); });
    return typeof GOLDMIND_STORE_ID !== 'undefined' && GOLDMIND_STORE_ID && typeof goldmindClient !== 'undefined';
  }
  async function loadBadges() {
    try {
      if (!(await storeReady())) return;
      var S = GOLDMIND_STORE_ID, key = 'gm_nav_badges_' + S, cached = null;
      try { cached = JSON.parse(sessionStorage.getItem(key) || 'null'); } catch (e) { /* ignore */ }
      if (cached && Date.now() - cached.t < 120000) { badges = cached.b; }
      else {
        var b = {};
        var q = await Promise.all([
          goldmindClient.from('pieces').select('id', { count: 'exact', head: true }).eq('store_id', S).eq('status', 'available'),
          goldmindClient.from('inventory_counts').select('status').eq('store_id', S).in('status', ['in_progress', 'completed']),
          goldmindClient.from('repair_tickets').select('id', { count: 'exact', head: true }).eq('store_id', S).eq('status', 'ready'),
          goldmindClient.from('gold_prices').select('karat, price_per_gram').eq('store_id', S)
        ].map(function (p) { return Promise.resolve(p).catch(function () { return {}; }); }));
        if (q[0] && q[0].count) b['inventory-list-ar.html'] = '<span class="gn-badge">' + q[0].count + '</span>';
        var counts = (q[1] && q[1].data) || [];
        if (counts.some(function (c) { return c.status === 'in_progress'; })) b['inventory-count-ar.html'] = '<span class="gn-badge amber" title="جرد جارٍ">جارٍ</span>';
        else if (counts.length) b['inventory-count-ar.html'] = '<span class="gn-badge amber" title="جرد مغلق ينتظر الترحيل">' + counts.length + '</span>';
        if (q[2] && q[2].count) b['repairs-ar.html'] = '<span class="gn-badge" title="جاهزة للتسليم">' + q[2].count + '</span>';
        var gp = ((q[3] && q[3].data) || []).filter(function (r) { return Number(r.price_per_gram) > 0; }).sort(function (x, y) { return x.karat - y.karat; })[0];
        if (gp) b['gold-price-ar.html'] = '<span class="gn-badge txt" dir="ltr">' + esc(gp.karat + 'K ' + Number(gp.price_per_gram).toFixed(2)) + '</span>';
        badges = b;
        try { sessionStorage.setItem(key, JSON.stringify({ t: Date.now(), b: b })); } catch (e) { /* ignore */ }
      }
      // overdue debts are worked out by the home screen; it leaves the counts here
      var od = null; try { od = JSON.parse(lsGet('gm_nav_overdue') || 'null'); } catch (e) { /* ignore */ }
      if (od && od.s === S) {
        if (od.c) badges['customers-ar.html'] = '<span class="gn-badge red" title="ديون متأخرة">' + od.c + '</span>';
        if (od.t) badges['ledger-ar.html'] = '<span class="gn-badge dot" title="تجار عليهم أرصدة متأخرة"></span>';
      }
      paintBadges();
    } catch (e) { /* badges are extras */ }
  }

  // Who is signed in, in which branch (+ switch when there are several)
  async function loadMe() {
    try {
      if (!(await storeReady()) || typeof GOLDMIND_STAFF_ID === 'undefined' || !GOLDMIND_STAFF_ID) return;
      var key = 'gm_nav_me_' + GOLDMIND_STAFF_ID + '_' + GOLDMIND_STORE_ID, me = null;
      try { me = JSON.parse(sessionStorage.getItem(key) || 'null'); } catch (e) { /* ignore */ }
      if (!me) {
        var r = await Promise.all([
          goldmindClient.from('staff').select('full_name, role').eq('id', GOLDMIND_STAFF_ID).maybeSingle(),
          goldmindClient.from('stores').select('name').eq('id', GOLDMIND_STORE_ID).maybeSingle(),
          Promise.resolve(goldmindClient.rpc('my_stores')).catch(function () { return {}; })
        ]);
        me = { n: (r[0].data && r[0].data.full_name) || '', role: r[0].data && r[0].data.role, store: (r[1].data && r[1].data.name) || '',
          many: Array.isArray(r[2] && r[2].data) && r[2].data.length > 1 };
        try { sessionStorage.setItem(key, JSON.stringify(me)); } catch (e) { /* ignore */ }
      }
      var ROLE = { owner: 'المالك', manager: 'مدير' };
      var box = document.querySelector('#gmNav .gn-me'); if (!box) return;
      box.innerHTML = '<div class="gn-av" aria-hidden="true">' + esc((me.n || '؟').trim().charAt(0)) + '</div>'
        + '<div class="gn-me-t"><b>' + esc(me.n || 'مستخدم') + (ROLE[me.role] ? ' — ' + ROLE[me.role] : '') + '</b><span>' + (me.store ? 'الفرع: ' + esc(me.store) : '') + '</span></div>'
        + (me.many ? '<a href="switch-branch-ar.html">تبديل الفرع</a>' : '');
      box.hidden = false;
    } catch (e) { /* card is an extra */ }
  }

  // Search (Ctrl+K): pages you can open, customers, traders, and a piece by barcode
  function norm(t) { return String(t || '').toLowerCase().replace(/[ً-ْـ]/g, '').replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي'); }
  var pal = null, palRows = [], palOn = 0, palSeq = 0;
  function palEnsure() {
    if (pal) return pal;
    pal = document.createElement('div'); pal.className = 'gm-pal-ov'; pal.setAttribute('role', 'dialog'); pal.setAttribute('aria-label', 'بحث');
    pal.innerHTML = '<div class="gm-pal"><div class="gm-pal-in"><span class="material-symbols-outlined" style="color:#8c6a22">search</span>'
      + '<input type="text" autocomplete="off" enterkeyhint="go" placeholder="ابحث عن صفحة أو زبون أو تاجر أو باركود…" aria-label="بحث"/><kbd>Esc</kbd><button type="button" aria-label="إغلاق البحث">إغلاق</button></div>'
      + '<div class="gm-pal-list" role="listbox"></div></div>';
    document.body.appendChild(pal);
    var input = pal.querySelector('input');
    pal.addEventListener('click', function (e) { if (e.target === pal) palClose(); });
    pal.querySelector('.gm-pal-in button').addEventListener('click', palClose);
    input.addEventListener('input', function () { palSearch(input.value); });
    input.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); palMove(e.key === 'ArrowDown' ? 1 : -1); }
      else if (e.key === 'Enter') { e.preventDefault(); var a = palRows[palOn]; if (a) a.click(); }
      else if (e.key === 'Escape') { e.preventDefault(); palClose(); }
    });
    return pal;
  }
  function palOpen() {
    palEnsure(); close();
    pal.classList.add('open');
    var input = pal.querySelector('input'); input.value = ''; palSearch('');
    input.focus(); setTimeout(function () { input.focus(); }, 30);
  }
  function palClose() { if (pal) pal.classList.remove('open'); }
  function palMove(n) {
    if (!palRows.length) return;
    palOn = (palOn + n + palRows.length) % palRows.length;
    palRows.forEach(function (r, i) { r.classList.toggle('on', i === palOn); });
    palRows[palOn].scrollIntoView({ block: 'nearest' });
  }
  function palPaint(groups) {
    var list = pal.querySelector('.gm-pal-list'), html = '';
    groups.forEach(function (g) {
      if (!g.rows.length) return;
      html += '<div class="gm-pal-g">' + g.t + '</div>' + g.rows.map(function (r) {
        return '<a class="gm-pal-row" role="option" href="' + esc(r.href) + '"><span class="material-symbols-outlined">' + r.i + '</span><span>' + esc(r.t) + '</span>' + (r.s ? '<small>' + esc(r.s) + '</small>' : '') + '</a>';
      }).join('');
    });
    list.innerHTML = html || '<div class="gm-pal-empty">لا نتائج. جرّب كلمة أخرى، أو اكتب باركود القطعة.</div>';
    palRows = Array.prototype.slice.call(list.querySelectorAll('.gm-pal-row'));
    palRows.forEach(function (r) {
      r.addEventListener('click', function (e) {
        if (r.getAttribute('href') === '#tz') { e.preventDefault(); palClose(); if (typeof gmOpenTimezonePicker === 'function') gmOpenTimezonePicker(); return; }
        palClose();
      });
    });
    palOn = 0; if (palRows[0]) palRows[0].classList.add('on');
  }
  function visiblePages() {
    var out = [], seen = {};
    document.querySelectorAll('#gmNav .gn-g a.gn-a').forEach(function (a) {
      if (a.style.display === 'none') return;
      var href = a.getAttribute('href'); if (seen[href]) return; seen[href] = 1;
      var x = linkDef(href); if (x) out.push({ href: href, i: x[1], t: x[2] });
    });
    return out;
  }
  async function palSearch(q) {
    var seq = ++palSeq, nq = norm(q.trim());
    var pages = visiblePages().filter(function (p) { return !nq || norm(p.t).indexOf(nq) !== -1; });
    if (!nq) {
      var fav = favs();
      pages.sort(function (a, b) { return (fav.indexOf(a.href) === -1) - (fav.indexOf(b.href) === -1); });
    }
    var groups = [{ t: 'صفحات', rows: pages.slice(0, nq ? 8 : 12) }];
    palPaint(groups);
    if (q.trim().length < 2 || !(await storeReady())) return;
    await new Promise(function (r) { setTimeout(r, 220); });
    if (seq !== palSeq) return;
    try {
      var term = q.trim().replace(/[%,()]/g, ' ');
      var stores = typeof gmOrgStoreIds === 'function' ? await gmOrgStoreIds().catch(function () { return [GOLDMIND_STORE_ID]; }) : [GOLDMIND_STORE_ID];
      if (!stores || !stores.length) stores = [GOLDMIND_STORE_ID];
      var r = await Promise.all([
        goldmindClient.from('customers').select('id, name, phone').in('store_id', stores).ilike('name', '%' + term + '%').limit(5),
        goldmindClient.from('traders').select('id, name').in('store_id', stores).ilike('name', '%' + term + '%').limit(5),
        goldmindClient.from('pieces').select('id, barcode, description_ar, weight_grams, status').eq('store_id', GOLDMIND_STORE_ID).eq('barcode', q.trim()).limit(3)
      ].map(function (p) { return Promise.resolve(p).catch(function () { return {}; }); }));
      if (seq !== palSeq) return;
      groups.push({ t: 'قطع', rows: ((r[2] && r[2].data) || []).map(function (p) { return { href: 'piece-edit-ar.html?id=' + p.id, i: 'qr_code_2', t: p.barcode + (p.description_ar ? ' — ' + p.description_ar : ''), s: p.weight_grams != null ? Number(p.weight_grams).toFixed(2) + ' غ' : '' }; }) });
      groups.push({ t: 'زبائن', rows: ((r[0] && r[0].data) || []).map(function (c) { return { href: 'customer-debts-ar.html?open=' + encodeURIComponent(c.id), i: 'person', t: c.name, s: c.phone || '' }; }) });
      groups.push({ t: 'تجار', rows: ((r[1] && r[1].data) || []).map(function (t) { return { href: 'ledger-ar.html?trader=' + encodeURIComponent(t.id), i: 'storefront', t: t.name }; }) });
      palPaint(groups);
    } catch (e) { /* pages stay listed */ }
  }
  window.gmOpenSearch = palOpen;
  document.addEventListener('keydown', function (e) {
    var typing = /^(input|textarea|select)$/i.test((e.target && e.target.tagName) || '') || (e.target && e.target.isContentEditable);
    if ((e.ctrlKey || e.metaKey) && !e.altKey && (e.key === 'k' || e.key === 'K' || e.key === 'ك')) { e.preventDefault(); palOpen(); return; }
    if (e.key === '[' && !typing && !e.ctrlKey && !e.metaKey && isDesk()) {
      var m = document.querySelector('#gmNav .gn-mini'); if (m) { e.preventDefault(); m.click(); }
    }
  });

  // ---- Glass pages + GoldMind emblem background + entrance motion (Bashar 2026-11-02) ----
  var GLASS_KEY = 'gm_glass';
  // pages drawn for a dark background (login screens: white text on the theme's dark colour) stay as designed
  function darkPage() { return !!(document.body && /(^|\s)text-white(\s|$)/.test(document.body.className)); }
  function glassOn() { return lsGet(GLASS_KEY) !== '0' && !darkPage(); } // on unless switched off on this device
  function applyGlass(on) {
    document.documentElement.classList.toggle('gm-glass', on);
    document.querySelectorAll('#gmNav .gn-pages button').forEach(function (b) { b.setAttribute('aria-checked', String((b.dataset.gl === '1') === on)); });
  }
  function mountGlassBg() {
    if (document.getElementById('gmGlassBg')) return;
    var desk = isDesk();
    var bg = document.createElement('div'); bg.id = 'gmGlassBg'; bg.setAttribute('aria-hidden', 'true');
    var ring = 'M159 58.7 A72 72 0 1 0 163.6 133.8 L163.6 108 L136 108';
    bg.innerHTML = '<svg viewBox="0 0 200 200" style="width:' + (desk ? 'min(1100px,150vw)' : '170vw') + ';height:auto;left:' + (desk ? '-18%' : '-55%') + ';top:' + (desk ? '-8%' : '6%') + ';opacity:.2">'
      + '<defs><linearGradient id="gmgg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FBE7A1"/><stop offset=".5" stop-color="#D4AF37"/><stop offset="1" stop-color="#8E6A1F"/></linearGradient>'
      + '<radialGradient id="gmss" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#FFF3C8" stop-opacity=".95"/><stop offset=".45" stop-color="#F5D77A" stop-opacity=".45"/><stop offset="1" stop-color="#F5D77A" stop-opacity="0"/></radialGradient>'
      + '<linearGradient id="gmcy" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#C9A04A"/><stop offset="1" stop-color="#7A5A1E"/></linearGradient>'
      + '<linearGradient id="gmau" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F3D27A"/><stop offset="1" stop-color="#B8862B"/></linearGradient></defs>'
      + '<g class="gms"><path class="gmr" d="' + ring + '" fill="none" stroke="url(#gmgg)" stroke-width="15" stroke-linecap="round" stroke-linejoin="round"/></g>'
      + '<g stroke-width="2.4" stroke-linecap="round" opacity=".9">'
      + '<g class="gmc"><line x1="66" y1="62" x2="66" y2="146" stroke="#A8822F"/><rect x="59.5" y="70" width="13" height="70" rx="3" fill="url(#gmcy)"/></g>'
      + '<g class="gmc"><line x1="86" y1="98" x2="86" y2="146" stroke="#D4AF37"/><rect x="79.5" y="106" width="13" height="34" rx="3" fill="url(#gmau)"/></g>'
      + '<g class="gmc"><line x1="106" y1="56" x2="106" y2="146" stroke="#A8822F"/><rect x="99.5" y="64" width="13" height="76" rx="3" fill="url(#gmcy)"/></g>'
      + '<g class="gmc"><line x1="126" y1="86" x2="126" y2="146" stroke="#D4AF37"/><rect x="119.5" y="94" width="13" height="46" rx="3" fill="url(#gmau)"/></g></g>'
      + '<path d="M66 58 L86 94 L106 52 L126 82 L136 96" fill="none" stroke="#fff" stroke-opacity=".8" stroke-width="1.8" stroke-linecap="round"/>'
      + '<circle class="gmt" cx="66" cy="58" r="7" fill="url(#gmss)"/><circle class="gmt" cx="106" cy="52" r="7" fill="url(#gmss)"/><circle class="gmt" cx="136" cy="96" r="7" fill="url(#gmss)"/></svg>'
      + (desk ? '<svg viewBox="0 0 200 200" style="width:340px;height:auto;right:22%;bottom:-90px;opacity:.14"><path d="' + ring + '" fill="none" stroke="url(#gmgg)" stroke-width="12" stroke-linecap="round"/></svg>' : '');
    document.body.insertBefore(bg, document.body.firstChild);
  }
  // icons on the page's buttons pop in one after another (only what is on screen at load)
  function popIcons() {
    var n = 0, h = window.innerHeight;
    document.querySelectorAll('main :is(a,button) .material-symbols-outlined').forEach(function (ic) {
      if (n >= 24) return;
      var r = ic.getBoundingClientRect();
      if (!r.width || r.top > h) return;
      ic.style.setProperty('--gm-i', n++); ic.classList.add('gm-pop');
    });
  }
  // Automated test browsers have no graphics card: blur and motion only slow them down (and make timing
  // tests flaky). There the glass colours, background and switches stay; blur and motion are off.
  var gmBot = !!navigator.webdriver;
  if (gmBot) document.documentElement.classList.add('gm-noblur'); else document.documentElement.classList.add('gm-anim');
  applyGlass(glassOn());

  function build() {
    var ov = document.createElement('div'); ov.id = 'gmNavOverlay';
    var d = document.createElement('aside'); d.id = 'gmNav'; d.setAttribute('aria-label', 'القائمة'); d.setAttribute('aria-hidden', 'true');
    var html = '<div class="gn-head"><b>GoldMind</b><button type="button" class="gn-mini" aria-label="تصغير القائمة" title="تصغير / توسيع القائمة"><span class="material-symbols-outlined">dock_to_left</span></button><button type="button" class="gn-x" aria-label="إغلاق القائمة"><span class="material-symbols-outlined">close</span></button></div>'
      + '<div class="gn-style" role="radiogroup" aria-label="شكل القائمة"><button type="button" role="radio" data-st="light"><span class="material-symbols-outlined">light_mode</span>فاتحة</button><button type="button" role="radio" data-st="dark"><span class="material-symbols-outlined">dark_mode</span>غامقة</button></div>'
      + '<div class="gn-pages"><span>الصفحات</span><div class="gn-style" role="radiogroup" aria-label="شكل الصفحات"><button type="button" role="radio" data-gl="1">زجاجية</button><button type="button" role="radio" data-gl="0">عادية</button></div></div>'
      + '<button type="button" class="gn-search" aria-label="بحث (Ctrl+K)"><span class="material-symbols-outlined">search</span><span class="gn-st">ابحث عن صفحة أو زبون أو باركود…</span><kbd>Ctrl K</kbd></button><nav>'
      + '<div class="gn-sec"><span>المفضّلة</span><button type="button" class="gn-favedit">تعديل</button></div><div class="gn-favlist"></div><div class="gn-sec"><span>كل الصفحات</span></div>';
    GROUPS.forEach(function (g) {
      var here = g.l.some(function (x) { return x[0] === page; });
      html += '<div class="gn-g' + (here ? ' open here-g' : '') + '"><button type="button" class="gn-h" aria-expanded="' + here + '"><span class="material-symbols-outlined gn-ic">' + g.i + '</span><span>' + esc(g.t) + '</span><span class="material-symbols-outlined gn-chev">expand_more</span></button><div class="gn-b"><div>';
      g.l.forEach(function (x) {
        html += linkHtml(x, false);
      });
      html += '</div></div></div>';
    });
    html += '</nav><div class="gn-foot"><div class="gn-me" hidden></div><button type="button" class="gn-out"><span class="material-symbols-outlined">logout</span>تسجيل الخروج</button></div>';
    d.innerHTML = html;
    document.body.appendChild(ov); document.body.appendChild(d);
    applyStyle(navStyle());
    applyGlass(glassOn());
    d.querySelectorAll('.gn-pages button').forEach(function (b) { b.addEventListener('click', function () { lsSet(GLASS_KEY, b.dataset.gl); applyGlass(b.dataset.gl === '1'); }); });
    d.querySelectorAll('.gn-style button[data-st]').forEach(function (b) { b.addEventListener('click', function () { lsSet(STYLE_KEY, b.dataset.st); applyStyle(b.dataset.st); }); });
    d.querySelector('.gn-search').addEventListener('click', palOpen);
    d.querySelector('.gn-favedit').addEventListener('click', function () {
      var on = d.classList.toggle('gn-editing');
      this.textContent = on ? 'تم' : 'تعديل';
    });
    // the star sits inside the link: it must not follow it
    d.addEventListener('click', function (e) {
      var st = e.target.closest && e.target.closest('.gn-star');
      if (!st) return;
      e.preventDefault(); e.stopPropagation(); toggleFav(st.dataset.href);
    });

    ov.addEventListener('click', close);
    d.querySelector('.gn-mini').addEventListener('click', function () {
      var mini = !document.documentElement.classList.contains('gm-mini');
      document.documentElement.classList.toggle('gm-mini', mini);
      try { localStorage.setItem('gm_nav_mini', mini ? '1' : ''); } catch (e) { /* ignore */ }
    });
    // in the small bar a link shows its name on hover
    d.querySelectorAll('a.gn-a').forEach(function (a) { a.title = (a.children[1] || a).textContent.trim(); });
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
    mountGlassBg();
    build();
    popIcons();
    renderFavs();
    addButton();
    setTimeout(applyPermissions, 600);
    setTimeout(function () { loadBadges(); loadMe(); }, 800);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();
})();
