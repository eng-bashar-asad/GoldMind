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

function gmMakeOverlayAt(rect, w, h) {
    const overlay = document.createElement('canvas');
    overlay.width = w; overlay.height = h;
    overlay.style.cssText = 'position:fixed;left:' + rect.left + 'px;top:' + rect.top + 'px;' +
        'width:' + rect.width + 'px;height:' + rect.height + 'px;z-index:99999;pointer-events:none;visibility:visible;';
    document.body.appendChild(overlay);
    return overlay;
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
                const px = p.x + p.vx * t;
                const py = p.y + 380 * t * t;
                const alpha = p.a * (1 - t);
                if (alpha <= 0.02) continue;
                ctx.fillStyle = 'rgba(' + p.r + ',' + p.g + ',' + p.b + ',' + alpha + ')';
                ctx.fillRect(px, py, p.size, p.size);
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
            const ease = 1 - Math.pow(1 - t, 3);
            ctx.clearRect(0, 0, cap.w, cap.h);
            for (const p of cap.particles) {
                const px = p.sx + (p.x - p.sx) * ease;
                const py = p.sy + (p.y - p.sy) * ease;
                const alpha = p.a * ease;
                ctx.fillStyle = 'rgba(' + p.r + ',' + p.g + ',' + p.b + ',' + alpha + ')';
                ctx.fillRect(px, py, p.size, p.size);
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
        const cap = await gmCaptureElement(document.body);
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
        // Let fonts/images/layout settle before the snapshot, while the
        // page is still normally visible (a hidden element captures blank).
        await new Promise(function (r) { setTimeout(r, 60); });
        const cap = await gmCaptureElement(document.body);
        document.body.style.visibility = 'hidden';
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

        const rectOut = outgoingEl.getBoundingClientRect();
        const capOut = await gmCaptureElement(outgoingEl);
        const overlayOut = gmMakeOverlayAt(rectOut, capOut.w, capOut.h);
        outgoingEl.style.visibility = 'hidden';
        await gmAnimateDissolve(overlayOut.getContext('2d'), capOut);
        overlayOut.remove();

        swapFn(); // actual DOM swap (hide outgoing, show incoming)
        outgoingEl.style.visibility = 'visible'; // reset for next time it's shown again

        await new Promise(function (r) { setTimeout(r, 30); }); // let layout settle
        const rectIn = incomingEl.getBoundingClientRect();
        const capIn = await gmCaptureElement(incomingEl);
        const overlayIn = gmMakeOverlayAt(rectIn, capIn.w, capIn.h);
        incomingEl.style.visibility = 'hidden';
        await gmAnimateReform(overlayIn.getContext('2d'), capIn);
        overlayIn.remove();
        incomingEl.style.visibility = 'visible';
    } catch (e) {
        outgoingEl.style.visibility = 'visible';
        incomingEl.style.visibility = 'visible';
        swapFn();
    }
}
