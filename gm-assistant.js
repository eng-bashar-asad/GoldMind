// GoldMind — in-app support assistant (chat). Loaded by supabase-config.js
// after sign-in (requireGoldMindSession), never on print/login pages.
// Talks to the `assistant` Edge Function with the user's own session, so it
// only ever sees this company's data and what this staff member may see.
// The conversation lives in sessionStorage (per company, per tab).
(function () {
  if (window.__gmAssistant || typeof goldmindClient === 'undefined') return;
  window.__gmAssistant = true;

  const KEY = 'gm_assistant_' + (window.GOLDMIND_STORE_ID || GOLDMIND_STORE_ID || '');
  const MAX_KEEP = 20;
  const SUGGEST = ['كيف أعمل فاتورة بيع؟', 'كيف أضيف موظفاً وأحدد صلاحياته؟', 'عندي مشكلة في البرنامج'];
  let msgs = [];
  try { msgs = JSON.parse(sessionStorage.getItem(KEY) || '[]'); } catch (e) { msgs = []; }
  const save = () => { try { sessionStorage.setItem(KEY, JSON.stringify(msgs.slice(-MAX_KEEP))); } catch (e) { /* full or blocked */ } };
  const esc = (s) => (typeof gmEscapeHtml === 'function' ? gmEscapeHtml(String(s)) : String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])));

  // Escaped text + **bold** + links to the app's own pages only.
  function render(text) {
    return esc(text)
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/\[([^\]]+)\]\(([\w-]+\.html)\)/g, '<a href="$2">$1</a>');
  }
  window.gmAssistantRender = render; // for tests

  const css = `
  .gma-btn{position:fixed;inset-inline-start:16px;bottom:calc(86px + env(safe-area-inset-bottom));z-index:49;width:52px;height:52px;border-radius:50%;border:0;cursor:pointer;
    background:var(--gm-primary,#7A6640);color:var(--gm-on-primary,#fff);display:flex;align-items:center;justify-content:center;box-shadow:0 8px 18px rgba(28,26,22,.25)}
  html.gm-desk .gma-btn{bottom:20px}
  .gma-btn:focus-visible,.gma-panel button:focus-visible,.gma-panel textarea:focus-visible{outline:2px solid var(--gm-accent,#C9A227);outline-offset:2px}
  .gma-panel{position:fixed;z-index:10030;inset-inline-start:12px;bottom:calc(12px + env(safe-area-inset-bottom));width:min(420px,calc(100vw - 24px));height:min(620px,calc(100dvh - 24px));
    display:none;flex-direction:column;direction:rtl;font-family:var(--gm-font-family,Arial),Arial,sans-serif;background:var(--gm-bg-elevated,#fff);color:var(--gm-on-surface,#1C1A16);
    border:1px solid var(--gm-outline-variant,#E4DAC0);border-radius:16px;box-shadow:0 18px 48px rgba(28,26,22,.28);overflow:hidden}
  .gma-panel.open{display:flex}.gma-panel.hidden{display:none}
  .gma-head{display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid var(--gm-outline-variant,#E4DAC0)}
  .gma-head h2{flex:1;margin:0;font-size:15px}
  .gma-ic{width:44px;height:44px;border:0;background:none;color:inherit;border-radius:10px;cursor:pointer;display:flex;align-items:center;justify-content:center}
  .gma-list{flex:1;overflow-y:auto;padding:12px;display:flex;flex-direction:column;gap:10px}
  .gma-m{max-width:88%;padding:9px 12px;border-radius:12px;font-size:14px;line-height:1.6;white-space:pre-wrap;overflow-wrap:anywhere}
  .gma-u{align-self:flex-start;background:var(--gm-primary,#7A6640);color:var(--gm-on-primary,#fff)}
  .gma-a{align-self:flex-end;background:var(--gm-surface-low,#F6F1E4);color:var(--gm-on-surface,#1C1A16)}
  .gma-a a{color:var(--gm-primary,#7A6640);font-weight:700}
  .gma-err{align-self:center;color:#B3261E;font-size:13px}
  .gma-hint{color:var(--gm-on-surface-variant,#5E5747);font-size:13px;margin:0}
  .gma-sug{display:flex;flex-wrap:wrap;gap:6px}
  .gma-sug button{min-height:44px;padding:0 12px;border-radius:999px;border:1px solid var(--gm-outline-variant,#E4DAC0);background:transparent;color:inherit;font:inherit;font-size:13px;cursor:pointer}
  .gma-form{display:flex;gap:8px;align-items:flex-end;padding:10px;border-top:1px solid var(--gm-outline-variant,#E4DAC0)}
  .gma-form textarea{flex:1;min-height:44px;max-height:120px;resize:none;border:1px solid var(--gm-outline-variant,#E4DAC0);border-radius:10px;padding:10px;font:inherit;font-size:16px;background:var(--gm-bg,#fff);color:inherit}
  .gma-send{width:44px;height:44px;border:0;border-radius:10px;background:var(--gm-primary,#7A6640);color:var(--gm-on-primary,#fff);cursor:pointer;display:flex;align-items:center;justify-content:center}
  .gma-send:disabled{opacity:.5;cursor:default}
  .gma-dots::after{content:'...';animation:gmaDots 1.2s steps(4) infinite;display:inline-block;width:1.2em;overflow:hidden;vertical-align:bottom}
  @keyframes gmaDots{from{width:0}to{width:1.2em}}
  @media (prefers-reduced-motion: reduce){.gma-dots::after{animation:none}}`;
  const st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  const btn = document.createElement('button');
  btn.type = 'button'; btn.className = 'gma-btn'; btn.id = 'gmAssistantBtn';
  btn.setAttribute('aria-label', 'مساعد GoldMind'); btn.setAttribute('aria-expanded', 'false');
  btn.innerHTML = '<span class="material-symbols-outlined" aria-hidden="true">support_agent</span>';

  const panel = document.createElement('section');
  // closed = class 'hidden': gm-nav.js treats any [role=dialog]:not(.hidden) as open
  // and pauses the phone gestures (swipe back, pull to refresh) while it is.
  panel.className = 'gma-panel hidden'; panel.id = 'gmAssistant'; panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-label', 'مساعد GoldMind');
  panel.innerHTML = `
    <div class="gma-head"><span class="material-symbols-outlined" aria-hidden="true">support_agent</span><h2>مساعد GoldMind</h2>
      <button type="button" class="gma-ic" id="gmaClear" aria-label="محادثة جديدة"><span class="material-symbols-outlined" aria-hidden="true">refresh</span></button>
      <button type="button" class="gma-ic" id="gmaClose" aria-label="إغلاق"><span class="material-symbols-outlined" aria-hidden="true">close</span></button></div>
    <div class="gma-list" id="gmaList" aria-live="polite"></div>
    <form class="gma-form" id="gmaForm">
      <textarea id="gmaInput" rows="1" maxlength="2000" placeholder="اكتب سؤالك..." aria-label="سؤالك للمساعد"></textarea>
      <button type="submit" class="gma-send" id="gmaSend" aria-label="إرسال"><span class="material-symbols-outlined" aria-hidden="true">send</span></button>
    </form>`;
  document.body.append(btn, panel);

  const list = panel.querySelector('#gmaList'), input = panel.querySelector('#gmaInput'), send = panel.querySelector('#gmaSend');
  let busy = false;

  function paint(extra) {
    if (!msgs.length) {
      list.innerHTML = '<p class="gma-hint">أهلاً، أنا مساعد GoldMind. اسألني عن أي خطوة في البرنامج، أو عن فاتورة أو قطعة بالرقم. للمشاكل التي تحتاج الإدارة أفتح لك طلب دعم.</p>'
        + '<div class="gma-sug">' + SUGGEST.map((s) => '<button type="button">' + esc(s) + '</button>').join('') + '</div>'
        + (extra || '');
      list.querySelectorAll('.gma-sug button').forEach((b) => { b.onclick = () => ask(b.textContent); });
      return;
    }
    list.innerHTML = msgs.map((m) => '<div class="gma-m ' + (m.role === 'user' ? 'gma-u">' + esc(m.content) : 'gma-a">' + render(m.content)) + '</div>').join('')
      + (extra || '');
    list.scrollTop = list.scrollHeight;
  }

  async function ask(text) {
    text = String(text || '').trim();
    if (!text || busy) return;
    busy = true; send.disabled = true; input.value = '';
    msgs.push({ role: 'user', content: text }); save();
    paint('<div class="gma-m gma-a gma-dots" aria-label="المساعد يكتب">يكتب</div>');
    let reply = null, err = null;
    try {
      const page = (location.pathname.split('/').pop() || '').slice(0, 80);
      const { data, error } = await goldmindClient.functions.invoke('assistant', {
        body: { messages: msgs.slice(-12), store_id: window.GOLDMIND_STORE_ID || GOLDMIND_STORE_ID, page },
      });
      if (error) {
        let m = null;
        try { m = (await error.context.json()).error; } catch (e) { /* not json */ }
        err = m || (navigator.onLine ? 'تعذّر الوصول للمساعد، حاول بعد قليل.' : 'لا يوجد اتصال بالإنترنت.');
      } else reply = data && data.reply;
    } catch (e) { err = 'تعذّر الوصول للمساعد، حاول بعد قليل.'; }
    if (reply) { msgs.push({ role: 'assistant', content: reply }); save(); paint(); }
    else { msgs.pop(); save(); paint('<p class="gma-err" role="alert">' + esc(err || 'لم يصل رد.') + '</p>'); input.value = text; }
    busy = false; send.disabled = false; input.focus();
  }

  function open(on) {
    panel.classList.toggle('open', on); panel.classList.toggle('hidden', !on); btn.style.display = on ? 'none' : '';
    btn.setAttribute('aria-expanded', String(on));
    if (on) { paint(); input.focus(); } else btn.focus();
  }
  btn.onclick = () => open(true);
  panel.querySelector('#gmaClose').onclick = () => open(false);
  panel.querySelector('#gmaClear').onclick = () => { msgs = []; save(); paint(); input.focus(); };
  panel.querySelector('#gmaForm').onsubmit = (e) => { e.preventDefault(); ask(input.value); };
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); ask(input.value); } });
  input.addEventListener('input', () => { input.style.height = 'auto'; input.style.height = Math.min(120, input.scrollHeight) + 'px'; });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && panel.classList.contains('open')) open(false); });
})();
