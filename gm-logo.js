// GoldMind animated logo: gold "G" + candlestick "M" with twinkling signal
// points, "GoldMind" wordmark, a sharp gold-price chart and the tagline
// GOLD ACCOUNTING INTELLIGENCE. Builds itself from nothing, then settles.
//
// Usage: <div data-gm-logo="lockup"></div>   full logo (login screens)
//        <div data-gm-logo="mark"></div>     emblem only, animated
//        <div data-gm-logo="header"></div>   small emblem + name (page headers)
// Optional: data-gm-static (no animation), data-gm-size="120" (emblem px).
// Tap/click the logo to replay the build. Honors prefers-reduced-motion.
(function () {
  'use strict';
  const G = 'M159 58.7 A72 72 0 1 0 163.6 133.8 L163.6 108 L136 108';
  const XS = [66, 86, 106, 126];
  const ACCENT = '#7FD6E8';
  const TAG = 'GOLD ACCOUNTING INTELLIGENCE';
  let uid = 0;

  const CSS = `
  .gm-logo{max-width:100%;display:inline-flex;flex-direction:column;align-items:stretch;gap:8px;direction:ltr;cursor:pointer;-webkit-tap-highlight-color:transparent;user-select:none}
  .gm-logo, .gm-logo *{font-family:'Cormorant Garamond',Georgia,'Times New Roman',serif !important}
  .gm-logo .gm-sans, .gm-logo .gm-sans *{font-family:Manrope,'Segoe UI',system-ui,sans-serif !important}
  .gm-logo .gm-ar{font-family:'El Messiri','Segoe UI',Arial,sans-serif !important}
  .gm-logo svg{overflow:visible;display:block}
  .gm-logo .gm-row{display:flex;align-items:center;gap:12px}
  .gm-logo .gm-word{font-weight:700;line-height:.95;display:flex;letter-spacing:.3px}
  .gm-logo .gm-gold{background:linear-gradient(180deg,#FBE7A1 0%,#D4AF37 55%,#9A7428 100%);-webkit-background-clip:text;background-clip:text;color:transparent}
  .gm-logo .gm-mind{color:#F4EFE3}
  .gm-logo[data-gm-logo="header"] .gm-mind{color:inherit}
  .gm-logo .gm-ar{color:#E9D9A6}
  .gm-logo .gm-tag{font-size:11px;letter-spacing:5px;color:#9FB0B4;white-space:nowrap;text-align:center}
  .gm-logo .gm-chart{position:relative}
  .gm-logo .gm-chip{position:absolute;right:-4px;top:-24px;font-size:11px;font-weight:700;padding:3px 8px;border-radius:999px;background:rgba(212,175,55,.12);border:1px solid rgba(212,175,55,.35);color:#FBE7A1;white-space:nowrap}
  .gm-anim .gm-d{stroke-dasharray:var(--len);stroke-dashoffset:var(--len);animation:gmLogoDraw .9s cubic-bezier(.2,.8,.2,1) both}
  .gm-anim .gm-g{transform-box:fill-box;transform-origin:bottom center;animation:gmLogoGrow .5s cubic-bezier(.2,.9,.3,1.3) both}
  .gm-anim .gm-r{display:inline-block;animation:gmLogoRise .5s cubic-bezier(.2,.8,.2,1) both}
  .gm-anim .gm-f{animation:gmLogoFade .8s ease-out both}
  .gm-anim .gm-p{transform-box:fill-box;transform-origin:center;animation:gmLogoPop .4s cubic-bezier(.2,.9,.3,1.5) both}
  .gm-logo .gm-spark{transform-box:fill-box;transform-origin:center;animation:gmLogoTwinkle 2.6s ease-in-out infinite}
  .gm-logo .gm-ping{transform-box:fill-box;transform-origin:center;opacity:0;animation:gmLogoPing 2.2s ease-out infinite}
  .gm-logo .gm-run{stroke-dasharray:40 700;opacity:0;animation:gmLogoRun 3.2s cubic-bezier(.4,0,.2,1) infinite}
  @keyframes gmLogoDraw{to{stroke-dashoffset:0}}
  @keyframes gmLogoGrow{from{transform:scaleY(0)}to{transform:scaleY(1)}}
  @keyframes gmLogoRise{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
  @keyframes gmLogoFade{from{opacity:0}to{opacity:1}}
  @keyframes gmLogoPop{from{opacity:0;transform:scale(0)}to{opacity:1;transform:scale(1)}}
  @keyframes gmLogoTwinkle{0%,100%{opacity:.25;transform:scale(.6) rotate(0)}45%{opacity:1;transform:scale(1.15) rotate(45deg)}60%{opacity:.9;transform:scale(1) rotate(60deg)}}
  @keyframes gmLogoPing{0%{opacity:.9;transform:scale(.6)}100%{opacity:0;transform:scale(2.8)}}
  @keyframes gmLogoRun{0%{opacity:0;stroke-dashoffset:740}10%{opacity:1}90%{opacity:1}100%{opacity:0;stroke-dashoffset:0}}
  .gm-static .gm-spark,.gm-static .gm-ping,.gm-static .gm-run{animation:none}
  .gm-static .gm-spark{opacity:.9}
  .gm-static .gm-run,.gm-static .gm-ping{display:none}
  @media (prefers-reduced-motion: reduce){
    .gm-logo .gm-d,.gm-logo .gm-g,.gm-logo .gm-r,.gm-logo .gm-f,.gm-logo .gm-p{animation:none!important;stroke-dashoffset:0!important;opacity:1!important;transform:none!important}
    .gm-logo .gm-spark{animation:none;opacity:.9}
    .gm-logo .gm-run,.gm-logo .gm-ping{display:none}
  }`;

  function injectAssets() {
    if (!document.getElementById('gm-logo-css')) {
      const s = document.createElement('style');
      s.id = 'gm-logo-css';
      s.textContent = CSS;
      document.head.appendChild(s);
    }
    if (!document.querySelector('link[data-gm-logo-font]')) {
      const l = document.createElement('link');
      l.rel = 'stylesheet';
      l.setAttribute('data-gm-logo-font', '');
      l.href = 'https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@700&family=El+Messiri:wght@500&family=Manrope:wght@600;700&display=swap';
      document.head.appendChild(l);
    }
  }

  // Candle tops trace the M; px/py (-0.5..0.5) let the pointer nudge them.
  function candleTops(px, py) { return [70 - px * 18, 106 + py * 10, 64 + px * 18, 94 - py * 8]; }

  function starPath(x, y) {
    const a = 7, b = 1.4;
    return `M${x} ${y - a} L${x + b} ${y - b} L${x + a} ${y} L${x + b} ${y + b} L${x} ${y + a} L${x - b} ${y + b} L${x - a} ${y} L${x - b} ${y - b} Z`;
  }

  function markSvg(id, size, delay) {
    const tops = candleTops(0, 0);
    const candles = tops.map((t, i) => {
      const x = XS[i], color = i % 2 ? '#D4AF37' : ACCENT;
      return `<g class="gm-g" data-candle="${i}" style="animation-delay:${(delay + 0.8 + i * 0.15).toFixed(2)}s">
        <line x1="${x}" y1="${t - 8}" x2="${x}" y2="146" stroke="${color}" stroke-width="2.4" stroke-linecap="round"/>
        <rect x="${x - 6.5}" y="${t}" width="13" height="${140 - t}" rx="3" fill="${color}"/></g>`;
    }).join('');
    const pts = XS.map((x, i) => [x, tops[i] - 12]).concat([[136, 96]]);
    const trend = 'M' + pts.map(p => p[0] + ' ' + p[1]).join(' L');
    const sparks = pts.map((p, i) => `<g class="gm-spark" data-spark="${i}" style="animation-delay:${(delay + 1.8 + i * 0.45).toFixed(2)}s">
        <circle cx="${p[0]}" cy="${p[1]}" r="7" fill="url(#${id}s)"/><path d="${starPath(p[0], p[1])}" fill="#fff"/>
        <circle cx="${p[0]}" cy="${p[1]}" r="2.2" fill="#FFF6D6"/></g>`).join('');
    return `<svg viewBox="0 0 200 200" width="${size}" height="${size}" aria-hidden="true">
      <defs>
        <linearGradient id="${id}g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FBE7A1"/><stop offset=".5" stop-color="#D4AF37"/><stop offset="1" stop-color="#8E6A1F"/></linearGradient>
        <radialGradient id="${id}s" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#FFF3C8" stop-opacity=".95"/><stop offset=".45" stop-color="#F5D77A" stop-opacity=".45"/><stop offset="1" stop-color="#F5D77A" stop-opacity="0"/></radialGradient>
      </defs>
      <path class="gm-d" d="${G}" fill="none" stroke="url(#${id}g)" stroke-width="15" stroke-linecap="round" stroke-linejoin="round" style="--len:420;animation-delay:${delay}s"/>
      ${candles}
      <path class="gm-d" data-trend d="${trend}" fill="none" stroke="#fff" stroke-opacity=".6" stroke-width="1.8" stroke-linecap="round" style="--len:120;animation-delay:${(delay + 1.5).toFixed(2)}s"/>
      ${sparks}
    </svg>`;
  }

  // Fixed chart shape: sharp zig-zag on a rising trend (drawn once, then still).
  const SERIES = Array.from({ length: 24 }, (_, i) =>
    Math.min(0.95, Math.max(0.05, 0.12 + i * 0.03 + (i % 2 ? 0.16 : -0.12) * (0.6 + Math.abs(Math.sin(i * 2.3))))));

  function chartSvg(id, width, delay) {
    const W = width - 12, step = W / (SERIES.length - 1);
    const P = SERIES.map((v, i) => [i * step, 44 - v * 42]);
    let line = `M${P[0][0].toFixed(1)} ${P[0][1].toFixed(1)}`;
    for (let i = 0; i < P.length - 1; i++) {
      const p0 = P[i - 1] || P[i], p1 = P[i], p2 = P[i + 1], p3 = P[i + 2] || p2;
      line += ` C${(p1[0] + (p2[0] - p0[0]) / 14).toFixed(1)} ${(p1[1] + (p2[1] - p0[1]) / 14).toFixed(1)} ${(p2[0] - (p3[0] - p1[0]) / 14).toFixed(1)} ${(p2[1] - (p3[1] - p1[1]) / 14).toFixed(1)} ${p2[0].toFixed(1)} ${p2[1].toFixed(1)}`;
    }
    const vols = SERIES.map((v, i) => {
      const d = i ? v - SERIES[i - 1] : 0, h = Math.min(12, 2 + Math.abs(d) * 90);
      return `<rect x="${(i * step - 3).toFixed(1)}" y="${(46 - h).toFixed(1)}" width="6" height="${h.toFixed(1)}" rx="1.5" fill="${d >= 0 ? 'rgba(212,175,55,.35)' : 'rgba(127,214,232,.3)'}"/>`;
    }).join('');
    const end = P[P.length - 1];
    return `<svg viewBox="0 0 ${width} 46" width="${width}" height="46" aria-hidden="true" data-chart data-step="${step}">
      <defs>
        <linearGradient id="${id}a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D4AF37" stop-opacity=".28"/><stop offset="1" stop-color="#D4AF37" stop-opacity="0"/></linearGradient>
        <linearGradient id="${id}r" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#8E6A1F" stop-opacity=".3"/><stop offset=".6" stop-color="#D4AF37"/><stop offset="1" stop-color="#FBE7A1"/></linearGradient>
      </defs>
      <g class="gm-f" style="animation-delay:${(delay + 0.7).toFixed(2)}s">${vols}<path d="${line} L${W} 46 L0 46 Z" fill="url(#${id}a)"/></g>
      <path class="gm-d" d="${line}" fill="none" stroke="url(#${id}r)" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" style="--len:700;animation-delay:${delay}s;animation-duration:1.2s"/>
      <path class="gm-run" d="${line}" fill="none" stroke="#FFF6D6" stroke-width="3.4" stroke-linecap="round" style="animation-delay:${(delay + 1.3).toFixed(2)}s"/>
      <g data-cross style="display:none"><line data-cx x1="0" y1="0" x2="0" y2="46" stroke="${ACCENT}" stroke-opacity=".6"/><circle data-cd r="3.6" fill="${ACCENT}" stroke="#0A1216" stroke-width="1.4"/></g>
      <circle class="gm-ping" cx="${W}" cy="${end[1].toFixed(1)}" r="6" fill="none" stroke="#FBE7A1" stroke-width="1.6" style="animation-delay:${(delay + 1.4).toFixed(2)}s"/>
      <circle class="gm-p" cx="${W}" cy="${end[1].toFixed(1)}" r="4" fill="#FBE7A1" style="animation-delay:${(delay + 1.1).toFixed(2)}s"/>
    </svg>`;
  }

  function letters(text, cls, start, gap) {
    return text.split('').map((ch, i) =>
      `<span class="gm-r ${cls || ''}" style="animation-delay:${(start + i * gap).toFixed(2)}s">${ch === ' ' ? '&nbsp;' : ch}</span>`).join('');
  }

  function wordmark(size, start) {
    return `<div class="gm-word" style="font-size:${size}px">${letters('Gold', 'gm-gold', start, 0.05)}${letters('Mind', 'gm-mind', start + 0.2, 0.05)}</div>`;
  }

  function render(el) {
    injectAssets();
    const id = 'gmL' + (++uid);
    const variant = el.getAttribute('data-gm-logo') || 'lockup';
    const isStatic = el.hasAttribute('data-gm-static');
    const size = parseInt(el.getAttribute('data-gm-size'), 10) || (variant === 'header' ? 40 : variant === 'mark' ? 120 : 112);
    el.classList.add('gm-logo');
    el.classList.toggle('gm-anim', !isStatic);
    el.classList.toggle('gm-static', isStatic);
    el.setAttribute('role', 'img');
    el.setAttribute('aria-label', 'GoldMind — Gold Accounting Intelligence');

    if (variant === 'mark') {
      el.innerHTML = markSvg(id, size, 0.1);
    } else if (variant === 'header') {
      el.innerHTML = `<div class="gm-row" style="gap:8px">${markSvg(id, size, 0)}${wordmark(Math.round(size * 0.62), 1.6)}</div>`;
    } else {
      // fit the space we're given (phones are narrow): emblem, chart and tagline scale with it
      const par = el.parentElement, cs = par ? getComputedStyle(par) : null;
      const avail = par ? par.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) : 380;
      const width = Math.max(220, Math.min(380, avail - 4));
      const mark = Math.min(size, Math.round(width * 0.29));
      const word = Math.round(mark * 0.42);
      const spacing = Math.max(1, Math.min(5, (width - TAG.length * 7.4) / TAG.length)).toFixed(1);
      el.innerHTML = `
        <div class="gm-row">${markSvg(id, mark, 0.1)}
          <div style="display:flex;flex-direction:column;align-items:flex-start;gap:4px">${wordmark(word, 1.8)}
            <div class="gm-ar gm-r" style="font-size:${Math.round(word * 0.4)}px;animation-delay:2.3s">جولد مايند</div></div></div>
        <div class="gm-chart" style="margin-top:14px">${chartSvg(id, width, 2.4)}
          <span class="gm-chip gm-sans gm-f" style="animation-delay:3.7s">XAU ▲ +3.20%</span></div>
        <div class="gm-tag gm-sans" style="letter-spacing:${spacing}px">${letters(TAG, '', 3.0, 0.03)}</div>`;
    }
    wire(el);
  }

  function wire(el) {
    if (el._gmWired) return;
    el._gmWired = true;
    // pointer nudges the candles (and sparks follow)
    el.addEventListener('pointermove', (e) => {
      const r = el.getBoundingClientRect();
      const px = (e.clientX - r.left) / r.width - 0.5, py = (e.clientY - r.top) / r.height - 0.5;
      const tops = candleTops(px, py);
      el.querySelectorAll('[data-candle]').forEach(g => {
        const i = +g.getAttribute('data-candle'), t = tops[i];
        g.querySelector('rect').setAttribute('y', t.toFixed(1));
        g.querySelector('rect').setAttribute('height', (140 - t).toFixed(1));
        g.querySelector('line').setAttribute('y1', (t - 8).toFixed(1));
      });
      const pts = XS.map((x, i) => [x, tops[i] - 12]).concat([[136, 96]]);
      const tr = el.querySelector('[data-trend]');
      if (tr) tr.setAttribute('d', 'M' + pts.map(p => p[0] + ' ' + p[1].toFixed(1)).join(' L'));
      el.querySelectorAll('[data-spark]').forEach(g => {
        const p = pts[+g.getAttribute('data-spark')];
        g.querySelectorAll('circle').forEach(c => { c.setAttribute('cx', p[0]); c.setAttribute('cy', p[1].toFixed(1)); });
        g.querySelector('path').setAttribute('d', starPath(p[0], +p[1].toFixed(1)));
      });
      // chart crosshair + price of the hovered point
      const chart = el.querySelector('[data-chart]');
      if (!chart) return;
      const cr = chart.getBoundingClientRect(), cross = chart.querySelector('[data-cross]'), chip = el.querySelector('.gm-chip');
      if (e.clientY < cr.top - 6 || e.clientY > cr.bottom + 6) { cross.style.display = 'none'; if (chip) chip.textContent = 'XAU ▲ +3.20%'; return; }
      const step = +chart.getAttribute('data-step'), vbW = +chart.viewBox.baseVal.width;
      const i = Math.max(0, Math.min(SERIES.length - 1, Math.round(((e.clientX - cr.left) / cr.width * vbW) / step)));
      const x = i * step, y = 44 - SERIES[i] * 42;
      cross.style.display = '';
      cross.querySelector('[data-cx]').setAttribute('x1', x); cross.querySelector('[data-cx]').setAttribute('x2', x);
      cross.querySelector('[data-cd]').setAttribute('cx', x); cross.querySelector('[data-cd]').setAttribute('cy', y);
      if (chip) chip.textContent = 'XAU ' + (4250 + SERIES[i] * 90).toFixed(2);
    });
    el.addEventListener('pointerleave', () => {
      const cross = el.querySelector('[data-cross]'), chip = el.querySelector('.gm-chip');
      if (cross) cross.style.display = 'none';
      if (chip) chip.textContent = 'XAU ▲ +3.20%';
    });
    // tap to watch it build again
    el.addEventListener('click', () => { if (!el.hasAttribute('data-gm-static')) render(el); });
  }

  window.gmRenderLogos = function (root) {
    (root || document).querySelectorAll('[data-gm-logo]').forEach(render);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => window.gmRenderLogos());
  else window.gmRenderLogos();
})();
