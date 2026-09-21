// gm-particle-transition.js
//
// "Disintegrate into grains, then reassemble" transition effect, in two
// flavors:
//   - gmDissolveNavigate(url): full-page version for real cross-page
//     navigation (captures/hides the whole body, navigates, then the
//     destination page reforms itself from grains on load).
//   - gmDissolveStepSwap(outgoingEl, incomingEl, swapFn): same effect for
//     swapping two sections within the SAME page (e.g. login-entry-ar.html's
//     step panels) — no navigation involved.
//
// Key rule: the INCOMING content must never be captured while it's really
// on screen — capturing takes real time (html2canvas isn't instant), and
// showing the final real content for that whole window before hiding it
// and playing the reform animation looks like "pops in fully, vanishes,
// then re-forms" instead of one smooth motion. So incoming content is
// always captured from an invisible off-screen clone instead, while the
// real element stays hidden the entire time until the animation lands.
//
// If anything goes wrong (html2canvas missing, capture fails, tainted
// canvas, etc.) everything here always falls back to an instant plain
// swap/navigation — this effect must never block the login flow.

const GM_TRANSITION_FLAG = 'gm_transition_pending';
const GM_TRANSITION_DURATION = 700;
const GM_TRANSITION_TARGET_PARTICLES = 3500;

function gmGrainSize(w, h) {
    return Math.max(4, Math.round(Math.sqrt((w * h) / GM_TRANSITION_TARGET_PARTICLES)));
}

function gmSampleParticles(imgCanvas, w, h, grain) {
    const ctx = imgCanvas.getContext('2d');
    const data = ctx.getImageData(0, 0, w, h).data;
    const particles = [];
    for (let y = 0; y < h; y += grain) {
        for (let x = 0; x < w; x += grain) {
            const i = (y * w + x) * 4;
            const a = data[i + 3];
            if (a < 20) continue; // skip transparent background — only real content crumbles
            particles.push({ x: x, y: y, r: data[i], g: data[i + 1], b: data[i + 2], a: a / 255, size: grain });
        }
    }
    return particles;
}

async function gmCaptureElement(el) {
    const snap = await html2canvas(el, { backgroundColor: null, logging: false, scale: 1 });
    const w = snap.width, h = snap.height;
    const buf = document.createElement('canvas');
    buf.width = w; buf.height = h;
    buf.getContext('2d').drawImage(snap, 0, 0);
    return { w: w, h: h, particles: gmSampleParticles(buf, w, h, gmGrainSize(w, h)) };
}

// Captures `el`'s final appearance via an invisible off-screen clone, so
// the real on-screen `el` never has to be visible during the (non-instant)
// capture. `applyFinalState`, if given, runs on the clone before capture
// (e.g. to remove a "hidden" class) so it reflects how el is ABOUT to look.
async function gmCaptureElementOffscreen(el, applyFinalState) {
    const rect = el.getBoundingClientRect();
    const clone = el.cloneNode(true);
    if (applyFinalState) applyFinalState(clone);
    clone.style.position = 'fixed';
    clone.style.left = '-10000px';
    clone.style.top = '0px';
    clone.style.width = rect.width + 'px';
    clone.style.boxSizing = 'border-box';
    clone.style.visibility = 'visible';
    document.body.appendChild(clone);
    try {
        const cap = await gmCaptureElement(clone);
        return cap;
    } finally {
        clone.remove();
    }
}

function gmMakeOverlayAt(rect, w, h) {
    const overlay = document.createElement('canvas');
    overlay.width = w; overlay.height = h;
    overlay.style.cssText = 'position:fixed;left:' + rect.left + 'px;top:' + rect.top + 'px;' +
        'width:' + rect.width + 'px;height:' + rect.height + 'px;z-index:99999;pointer-events:none;visibility:visible;';
    document.body.appendChild(overlay);
    return overlay;
}

// Pure per-particle position math, shared by the time-driven animations
// below AND by the scroll-scrubbed version further down -- kept in one
// place so both stay visually identical.
function gmDissolvePos(p, t2) {
    return { x: p.x + p.vx * t2, y: p.y + 380 * t2 * t2, alpha: p.a * (1 - t2) };
}
function gmReformPos(p, t2) {
    const ease = 1 - Math.pow(1 - t2, 3);
    return { x: p.sx + (p.x - p.sx) * ease, y: p.sy + (p.y - p.sy) * ease, alpha: p.a * ease };
}

// Particles fall apart with gravity and fade out. Resolves when done.
function gmAnimateDissolve(ctx, cap) {
    cap.particles.forEach(function (p) { p.vx = (Math.random() - 0.5) * 140; });
    return new Promise(function (resolve) {
        const start = performance.now();
        function frame(now) {
            const t = Math.min(1, (now - start) / GM_TRANSITION_DURATION);
            ctx.clearRect(0, 0, cap.w, cap.h);
            for (const p of cap.particles) {
                const pos = gmDissolvePos(p, t);
                if (pos.alpha <= 0.02) continue;
                ctx.fillStyle = 'rgba(' + p.r + ',' + p.g + ',' + p.b + ',' + pos.alpha + ')';
                ctx.fillRect(pos.x, pos.y, p.size, p.size);
            }
            if (t < 1) requestAnimationFrame(frame); else resolve();
        }
        requestAnimationFrame(frame);
    });
}

// Particles fly in from scattered positions above and settle into place,
// fading in. Resolves when done.
function gmAnimateReform(ctx, cap) {
    cap.particles.forEach(function (p) {
        p.sx = p.x + (Math.random() - 0.5) * 260;
        p.sy = p.y - 260 - Math.random() * 220;
    });
    return new Promise(function (resolve) {
        const start = performance.now();
        function frame(now) {
            const t = Math.min(1, (now - start) / GM_TRANSITION_DURATION);
            ctx.clearRect(0, 0, cap.w, cap.h);
            for (const p of cap.particles) {
                const pos = gmReformPos(p, t);
                if (pos.alpha <= 0.02) continue;
                ctx.fillStyle = 'rgba(' + p.r + ',' + p.g + ',' + p.b + ',' + pos.alpha + ')';
                ctx.fillRect(pos.x, pos.y, p.size, p.size);
            }
            if (t < 1) requestAnimationFrame(frame); else resolve();
        }
        requestAnimationFrame(frame);
    });
}


// ---------- Cross-page navigation ----------

async function gmDissolveNavigate(url) {
    try {
        if (typeof html2canvas === 'undefined') { window.location.href = url; return; }
        const cap = await gmCaptureElement(document.body); // outgoing: real page is genuinely on screen here, that's correct
        const overlay = gmMakeOverlayAt({ left: 0, top: 0 }, cap.w, cap.h);
        document.body.style.visibility = 'hidden';
        await gmAnimateDissolve(overlay.getContext('2d'), cap);
        sessionStorage.setItem(GM_TRANSITION_FLAG, '1');
        window.location.href = url;
    } catch (e) {
        window.location.href = url; // never let the effect block navigation
    }
}

async function gmReformOnLoad() {
    if (sessionStorage.getItem(GM_TRANSITION_FLAG) !== '1') return;
    sessionStorage.removeItem(GM_TRANSITION_FLAG);
    try {
        if (typeof html2canvas === 'undefined') return;
        // Hide the real page immediately — before any capture — so it is
        // never shown fully-formed even for a moment. We capture a
        // duplicate off-screen instead.
        document.body.style.visibility = 'hidden';
        // Let fonts/images/layout settle before the snapshot.
        await new Promise(function (r) { setTimeout(r, 60); });
        const cap = await gmCaptureElementOffscreen(document.body);
        const overlay = gmMakeOverlayAt({ left: 0, top: 0 }, cap.w, cap.h);
        await gmAnimateReform(overlay.getContext('2d'), cap);
        overlay.remove();
        document.body.style.visibility = 'visible';
    } catch (e) {
        document.body.style.visibility = 'visible';
    }
}

document.addEventListener('DOMContentLoaded', gmReformOnLoad);

// ---------- Same-page section swap (e.g. login step panels) ----------

async function gmDissolveStepSwap(outgoingEl, incomingEl, swapFn) {
    try {
        if (typeof html2canvas === 'undefined') { swapFn(); return; }

        // 1) Dissolve the outgoing panel — it's genuinely on screen, capture it as-is.
        const rectOut = outgoingEl.getBoundingClientRect();
        const capOut = await gmCaptureElement(outgoingEl);
        const overlayOut = gmMakeOverlayAt(rectOut, capOut.w, capOut.h);
        outgoingEl.style.visibility = 'hidden';
        await gmAnimateDissolve(overlayOut.getContext('2d'), capOut);
        overlayOut.remove();

        // 2) Swap the DOM, but hide the incoming panel in the very same
        // tick — before the browser paints — so it's never seen fully
        // formed. Its true appearance is captured from an off-screen clone.
        swapFn();
        incomingEl.style.visibility = 'hidden';
        outgoingEl.style.visibility = 'visible'; // reset for next time it's shown again

        await new Promise(function (r) { requestAnimationFrame(function () { requestAnimationFrame(r); }); });
        const rectIn = incomingEl.getBoundingClientRect();
        const capIn = await gmCaptureElementOffscreen(incomingEl);
        const overlayIn = gmMakeOverlayAt(rectIn, capIn.w, capIn.h);
        await gmAnimateReform(overlayIn.getContext('2d'), capIn);
        overlayIn.remove();
        incomingEl.style.visibility = 'visible';
    } catch (e) {
        outgoingEl.style.visibility = 'visible';
        incomingEl.style.visibility = 'visible';
        swapFn();
    }
}

// ---------- Static image "reform" (e.g. a hero logo entrance) ----------
// Loads a plain <img> or <object type="image/svg+xml"> element's real
// image, samples it into a particle grid, and animates the particles
// flying in from scattered positions and converging into place -- same
// motion as gmAnimateReform, but for a one-off entrance rather than a
// step/page transition. No html2canvas needed here since the source is
// already a plain image. The real element stays hidden until particles
// land, then it's revealed and the overlay removed. Never blocks: any
// failure (missing image, zero-size box, reduced-motion) just shows the
// real element immediately.
function gmParticleImageIntro(imgEl) {
    return new Promise(function (resolveOuter) {
        const done = function () { imgEl.style.visibility = 'visible'; resolveOuter(); };
        try {
            if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) { done(); return; }
            const src = imgEl.tagName === 'OBJECT' ? imgEl.data : (imgEl.currentSrc || imgEl.src);
            const rect = imgEl.getBoundingClientRect();
            const w = Math.round(rect.width), h = Math.round(rect.height);
            if (!src || !w || !h) { done(); return; }
            const img = new Image();
            img.onload = function () {
                try {
                    const buf = document.createElement('canvas');
                    buf.width = w; buf.height = h;
                    buf.getContext('2d').drawImage(img, 0, 0, w, h);
                    const particles = gmSampleParticles(buf, w, h, gmGrainSize(w, h));
                    imgEl.style.visibility = 'hidden';
                    const overlay = gmMakeOverlayAt(rect, w, h);
                    gmAnimateReform(overlay.getContext('2d'), { w: w, h: h, particles: particles }).then(function () {
                        overlay.remove();
                        done();
                    });
                } catch (e) { done(); }
            };
            img.onerror = function () { done(); };
            img.src = src;
        } catch (e) { done(); }
    });
}

// ---------- Scroll-scrubbed dissolve/reform (e.g. hero logo -> headline) ----------
//
// Ties the SAME dissolve/reform particle motion above directly to scroll
// position instead of time, so it's fully reversible: scroll down and the
// outgoing element (outEl) dissolves into particles while the incoming
// element (inEl) reforms from them; scroll back up and it runs in
// reverse, at whatever point the user stopped.
//
// zoneEl must be a tall wrapper (e.g. height: 200vh) with a
// `.hero-scroll-pin` child that stays pinned on screen (position: sticky)
// while the zone scrolls past -- that pinned box is what outEl/inEl sit
// inside, absolutely stacked on top of each other. Progress (t) is
// derived from how far the zone has scrolled past the top of the
// viewport. Never blocks: any failure just shows both elements normally.
async function gmScrollParticleZone(zoneEl, outEl, inEl) {
    const showBoth = function () { outEl.style.visibility = 'visible'; inEl.style.visibility = 'visible'; };
    try {
        if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) { showBoth(); return; }
        if (typeof html2canvas === 'undefined') { showBoth(); return; }

        const pin = zoneEl.querySelector('.hero-scroll-pin');
        if (!pin) { showBoth(); return; }

        // outEl is genuinely on screen right now -> capture as-is.
        const capOut = await gmCaptureElement(outEl);
        // inEl isn't shown yet -> capture from an off-screen clone.
        const capIn = await gmCaptureElementOffscreen(inEl, function (clone) { clone.style.visibility = 'visible'; });

        // Randomized per-particle drift/entry offsets, assigned ONCE so the
        // scrub is stable and reversible rather than re-randomized per frame.
        capOut.particles.forEach(function (p) { p.vx = (Math.random() - 0.5) * 140; });
        capIn.particles.forEach(function (p) {
            p.sx = p.x + (Math.random() - 0.5) * 260;
            p.sy = p.y - 260 - Math.random() * 220;
        });

        const pinRect = pin.getBoundingClientRect();
        const outRect = outEl.getBoundingClientRect();
        const inRect = inEl.getBoundingClientRect(); // visibility:hidden keeps layout, so this is meaningful
        const outOffX = outRect.left - pinRect.left, outOffY = outRect.top - pinRect.top;
        const inOffX = inRect.left - pinRect.left, inOffY = inRect.top - pinRect.top;

        const overlay = document.createElement('canvas');
        overlay.width = Math.round(pinRect.width);
        overlay.height = Math.round(pinRect.height);
        overlay.style.cssText = 'position:fixed;left:' + pinRect.left + 'px;top:' + pinRect.top + 'px;' +
            'width:' + pinRect.width + 'px;height:' + pinRect.height + 'px;z-index:5;pointer-events:none;display:none;';
        pin.appendChild(overlay);
        const ctx = overlay.getContext('2d');

        let ticking = false;
        function render() {
            ticking = false;
            const zRect = zoneEl.getBoundingClientRect();
            const scrollable = zoneEl.offsetHeight - window.innerHeight;
            const t = scrollable > 0 ? Math.min(1, Math.max(0, -zRect.top / scrollable)) : 0;

            if (t <= 0.001) {
                overlay.style.display = 'none';
                outEl.style.visibility = 'visible'; inEl.style.visibility = 'hidden';
                return;
            }
            if (t >= 0.999) {
                overlay.style.display = 'none';
                outEl.style.visibility = 'hidden'; inEl.style.visibility = 'visible';
                return;
            }
            outEl.style.visibility = 'hidden'; inEl.style.visibility = 'hidden';
            overlay.style.display = 'block';
            ctx.clearRect(0, 0, overlay.width, overlay.height);
            if (t <= 0.5) {
                const t2 = t / 0.5;
                for (const p of capOut.particles) {
                    const pos = gmDissolvePos(p, t2);
                    if (pos.alpha <= 0.02) continue;
                    ctx.fillStyle = 'rgba(' + p.r + ',' + p.g + ',' + p.b + ',' + pos.alpha + ')';
                    ctx.fillRect(outOffX + pos.x, outOffY + pos.y, p.size, p.size);
                }
            } else {
                const t2 = (t - 0.5) / 0.5;
                for (const p of capIn.particles) {
                    const pos = gmReformPos(p, t2);
                    if (pos.alpha <= 0.02) continue;
                    ctx.fillStyle = 'rgba(' + p.r + ',' + p.g + ',' + p.b + ',' + pos.alpha + ')';
                    ctx.fillRect(inOffX + pos.x, inOffY + pos.y, p.size, p.size);
                }
            }
        }
        function onScroll() { if (!ticking) { ticking = true; requestAnimationFrame(render); } }
        window.addEventListener('scroll', onScroll, { passive: true });
        window.addEventListener('resize', onScroll);
        render();
    } catch (e) {
        showBoth();
    }
}
