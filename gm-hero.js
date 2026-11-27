// Animated GoldMind brand artwork behind the login screens (بشار 2026-11-16):
// the gold G with candlesticks, a slow breathing zoom, a light sweep, candle glow and rising embers.
// Used by login-entry-ar.html and login-ar-4.html — one place, so every sign-in screen looks the same.
// Phone/tablet: artwork on top, the form on its reflective floor. Computer: artwork left, form right.
(function () {
  var css = `/* ===== Brand hero (بشار 2026-11-16): the GoldMind G artwork behind the login, with motion ===== */
:root { --gm-hero-bg: #020307; }
html, body { background-color: var(--gm-hero-bg) !important; }
/* the form waits for the artwork so the screen doesn't flash its old layout first */
body:not(.gm-hero-page) > main { visibility: hidden; }
.gm-hero { position: absolute; top: 0; left: 50%; width: min(100vw, 560px); aspect-ratio: 1; transform: translateX(-50%); overflow: hidden; pointer-events: none; z-index: 0;
  -webkit-mask-image: linear-gradient(to right, transparent, #000 9%, #000 91%, transparent), linear-gradient(to bottom, #000 80%, transparent);
  -webkit-mask-composite: source-in;
  mask-image: linear-gradient(to right, transparent, #000 9%, #000 91%, transparent), linear-gradient(to bottom, #000 80%, transparent); mask-composite: intersect; }
.gm-hero img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; animation: gmHeroBreath 14s ease-in-out infinite alternate, gmHeroIn 1.4s cubic-bezier(.2,.8,.2,1) both; transform-origin: 50% 40%; }
@keyframes gmHeroIn { from { opacity: 0; filter: brightness(1.8) saturate(.4); } to { opacity: 1; filter: none; } }
@keyframes gmHeroBreath { from { transform: scale(1); } to { transform: scale(1.05) translateY(-1%); } }
/* a light band sweeping across the gold every few seconds */
.gm-hero-shine { position: absolute; inset: 0; background: linear-gradient(105deg, transparent 38%, rgba(255,236,170,.55) 48%, rgba(255,255,255,.75) 50%, rgba(255,236,170,.55) 52%, transparent 62%);
  background-size: 260% 100%; mix-blend-mode: overlay; animation: gmHeroSweep 6.5s ease-in-out 1.2s infinite; }
@keyframes gmHeroSweep { 0% { background-position: 130% 0; opacity: 0; } 8% { opacity: 1; } 45% { background-position: -30% 0; opacity: 1; } 50%, 100% { background-position: -30% 0; opacity: 0; } }
/* the candle tips twinkle */
.gm-hero-glow { position: absolute; left: 30%; top: 22%; width: 42%; height: 38%; background: radial-gradient(ellipse at center, rgba(255,210,110,.35), transparent 65%); mix-blend-mode: screen; animation: gmHeroGlow 3.2s ease-in-out infinite alternate; }
@keyframes gmHeroGlow { from { opacity: .15; } to { opacity: .8; } }
/* embers rising */
.gm-hero-sparks i { position: absolute; left: var(--x); top: var(--y); width: var(--s); height: var(--s); border-radius: 50%; background: #ffd77a; box-shadow: 0 0 6px 2px rgba(255,190,80,.7); opacity: 0;
  animation: gmEmber var(--d) linear var(--w) infinite; }
@keyframes gmEmber { 0% { transform: translate(0,0); opacity: 0; } 12% { opacity: .95; } 80% { opacity: .5; } 100% { transform: translate(var(--dx), -220px); opacity: 0; } }
/* the form sits on the reflective floor, under the GoldMind wordmark */
.gm-hero-spacer { height: calc(min(100vw, 560px) * .84); flex-shrink: 0; }
body.gm-hero-page { justify-content: flex-start !important; }
/* sign-in card in the artwork's style (بشار 2026-11-16): black glass, bevelled gold frame, molten-gold buttons */
.gm-hero-page .glass-panel { position: relative; background: linear-gradient(160deg, rgba(22,20,14,.86), rgba(6,7,10,.9) 55%, rgba(14,12,8,.9)) !important;
  border: 1px solid transparent !important; backdrop-filter: blur(12px); border-radius: 18px !important;
  box-shadow: 0 30px 80px -20px rgba(0,0,0,.9), 0 0 60px -25px rgba(232,190,90,.35), inset 0 1px 0 rgba(255,236,170,.12) !important; }
.gm-hero-page .glass-panel::before { content: ""; position: absolute; inset: 0; border-radius: inherit; padding: 1px; pointer-events: none;
  background: linear-gradient(135deg, #FFF1B8, #C9982E 25%, #5E4312 50%, #E9C35E 75%, #8A6418);
  -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0); -webkit-mask-composite: xor; mask-composite: exclude; }
.gm-hero-page .glass-panel h2 { font-size: 1.45rem; background: linear-gradient(180deg, #FFF3C4, #E7C25B 55%, #A87A1E); -webkit-background-clip: text; background-clip: text; color: transparent !important; }
.gm-hero-page .gold-gradient { position: relative; overflow: hidden; color: #1A1206 !important; border-radius: 12px !important;
  background: linear-gradient(180deg, #FCEBA6 0%, #E8C25A 38%, #C8962C 70%, #9C6F1B 100%) !important;
  box-shadow: inset 0 1px 0 rgba(255,250,220,.85), inset 0 -2px 0 rgba(90,60,10,.45), 0 10px 26px -10px rgba(232,180,60,.6) !important; }
.gm-hero-page .gold-gradient::after { content: ""; position: absolute; inset: 0; pointer-events: none;
  background: linear-gradient(105deg, transparent 40%, rgba(255,255,255,.55) 50%, transparent 60%); background-size: 260% 100%; animation: gmBtnShine 6s ease-in-out infinite; }
@keyframes gmBtnShine { 0%, 70% { background-position: 130% 0; } 100% { background-position: -30% 0; } }
.gm-hero-page .gm-btn-line { border-radius: 12px !important; color: #F3DC92 !important; border: 1px solid rgba(232,194,90,.55) !important;
  background: linear-gradient(180deg, rgba(232,194,90,.10), rgba(232,194,90,.02)) !important; }
.gm-hero-page .gm-btn-line:hover { background: linear-gradient(180deg, rgba(232,194,90,.18), rgba(232,194,90,.05)) !important; }
.gm-hero-page .gm-bi { display: inline-flex; align-items: center; justify-content: center; gap: .6rem; }
.gm-hero-page .gm-bi .material-symbols-outlined { font-size: 1.5rem; }
.gm-hero-page input { border-radius: 10px; }
@media (min-width: 1024px) and (min-aspect-ratio: 4/3) {
  /* computer: the artwork fills the left side, the login on the right */
  /* artwork pulled in from the left edge so it sits nearer the middle and reads bigger */
  .gm-hero { position: fixed; top: 50%; left: clamp(0px, 7vw, 130px); width: min(64vw, 104vh); transform: translateY(-50%);
    -webkit-mask-image: linear-gradient(to right, transparent 0, #000 9%, #000 72%, transparent 100%), linear-gradient(to bottom, #000 85%, transparent 100%);
    -webkit-mask-composite: source-in; mask-image: linear-gradient(to right, transparent 0, #000 9%, #000 72%, transparent 100%), linear-gradient(to bottom, #000 85%, transparent 100%); mask-composite: intersect; }
  body.gm-hero-page { justify-content: center !important; align-items: flex-start !important; padding-inline-start: max(4vw, 32px); }
  .gm-hero-spacer { display: none; }
  /* the sign-in column is bigger on a computer so it matches the artwork */
  body.gm-hero-page main { max-width: 520px !important; }
  .gm-hero-page .glass-panel { padding: 2.75rem 2.5rem !important; }
  .gm-hero-page .glass-panel h2 { font-size: 1.9rem; }
  .gm-hero-page .glass-panel h2 + p { font-size: 1.05rem; }
  .gm-hero-page .glass-panel .gm-bi { font-size: 1.2rem; }
  .gm-hero-page .glass-panel button.py-5 { padding-block: 1.45rem; font-size: 1.3rem; }
  .gm-hero-page main > .text-center p { font-size: 1.25rem; letter-spacing: .3px; color: #F1DE9E !important; }
}
@media (prefers-reduced-motion: reduce) {
  .gm-hero img, .gm-hero-shine, .gm-hero-glow, .gm-hero-sparks i { animation: none !important; }
  .gm-hero-shine, .gm-hero-sparks { display: none; }
}`;
  var st = document.createElement('style'); st.id = 'gm-hero-style'; st.textContent = css;
  (document.head || document.documentElement).appendChild(st);
  // runs from <head> (not deferred): fetch the artwork right away
  // sharper artwork (بشار 2026-11-27): AI-upscaled 4× master, served at the size the screen needs
  var HERO_SET = 'goldmind-hero.jpg 1024w, goldmind-hero-1536.jpg 1536w, goldmind-hero-2048.jpg 2048w', HERO_SIZES = '(min-width: 1024px) and (min-aspect-ratio: 4/3) min(64vw, 104vh), min(100vw, 560px)';
  var pl = document.createElement('link'); pl.rel = 'preload'; pl.as = 'image'; pl.href = 'goldmind-hero.jpg';
  pl.setAttribute('imagesrcset', HERO_SET); pl.setAttribute('imagesizes', HERO_SIZES);
  (document.head || document.documentElement).appendChild(pl);
  function mount() {
    if (document.querySelector('.gm-hero')) return;
    var main = document.querySelector('main'); if (!main) return;
    document.body.classList.add('gm-hero-page');
    var wrap = document.createElement('div');
    wrap.innerHTML = '<div class="gm-hero" aria-hidden="true"><img src="goldmind-hero.jpg" srcset="' + HERO_SET + '" sizes="' + HERO_SIZES + '" alt="" width="1024" height="1024" decoding="async" fetchpriority="high"/>' +
      '<div class="gm-hero-glow"></div><div class="gm-hero-shine"></div><div class="gm-hero-sparks">' + '<i style="--x:45%;--y:64%;--s:4px;--d:7.6s;--w:0.5s;--dx:4px"></i><i style="--x:16%;--y:78%;--s:5px;--d:5.2s;--w:3.6s;--dx:-28px"></i><i style="--x:15%;--y:82%;--s:4px;--d:5.3s;--w:0.6s;--dx:-3px"></i><i style="--x:11%;--y:91%;--s:2px;--d:8.8s;--w:4.4s;--dx:7px"></i><i style="--x:11%;--y:91%;--s:5px;--d:6.6s;--w:6.8s;--dx:-28px"></i><i style="--x:75%;--y:63%;--s:3px;--d:6.7s;--w:3.8s;--dx:6px"></i><i style="--x:43%;--y:90%;--s:3px;--d:5.4s;--w:4.0s;--dx:-18px"></i><i style="--x:51%;--y:61%;--s:5px;--d:7.8s;--w:4.0s;--dx:9px"></i><i style="--x:30%;--y:86%;--s:5px;--d:6.7s;--w:2.2s;--dx:7px"></i><i style="--x:62%;--y:78%;--s:3px;--d:6.0s;--w:1.3s;--dx:19px"></i><i style="--x:35%;--y:60%;--s:5px;--d:6.2s;--w:3.5s;--dx:-9px"></i><i style="--x:61%;--y:73%;--s:5px;--d:8.9s;--w:0.8s;--dx:-4px"></i><i style="--x:25%;--y:76%;--s:3px;--d:8.7s;--w:3.0s;--dx:12px"></i><i style="--x:13%;--y:90%;--s:5px;--d:8.2s;--w:5.7s;--dx:-9px"></i><i style="--x:92%;--y:77%;--s:5px;--d:7.0s;--w:5.6s;--dx:-26px"></i><i style="--x:15%;--y:72%;--s:4px;--d:7.8s;--w:0.5s;--dx:16px"></i><i style="--x:93%;--y:74%;--s:5px;--d:9.0s;--w:5.8s;--dx:-12px"></i><i style="--x:95%;--y:79%;--s:3px;--d:5.1s;--w:3.2s;--dx:-20px"></i>' + '</div></div>' +
      '<div class="gm-hero-spacer" aria-hidden="true"></div>';
    while (wrap.firstChild) main.parentNode.insertBefore(wrap.firstChild, main);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();
})();
