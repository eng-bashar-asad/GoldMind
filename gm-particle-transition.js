// gm-particle-transition.js
//
// "Disintegrate into grains, then reassemble" page transition, used
// between the login-flow pages. The outgoing page is snapshotted,
// broken into small colored squares, and blown apart/faded out; the
// incoming page reverses the effect (grains fly in and settle into
// the real page). If anything goes wrong (html2canvas missing, capture
// fails, etc.) this always falls back to a plain instant navigation —
// the login flow must never be blocked by a broken animation.
//
// Usage: call gmDissolveNavigate('some-page.html') instead of setting
// window.location.href directly. The destination page just needs this
// same script included; the reform animation runs itself on load.

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

async function gmCaptureBody() {
    const snap = await html2canvas(document.body, { backgroundColor: null, logging: false, scale: 1 });
    const w = snap.width, h = snap.height;
    const buf = document.createElement('canvas');
    buf.width = w; buf.height = h;
    buf.getContext('2d').drawImage(snap, 0, 0);
    return { w: w, h: h, grain: gmGrainSize(w, h), particles: gmSampleParticles(buf, w, h, gmGrainSize(w, h)) };
}

function gmMakeOverlay(w, h) {
    const overlay = document.createElement('canvas');
    overlay.width = w; overlay.height = h;
    overlay.style.cssText = 'position:fixed;inset:0;width:100vw;height:100vh;z-index:99999;pointer-events:none;visibility:visible;';
    document.body.appendChild(overlay);
    return overlay;
}

async function gmDissolveNavigate(url) {
    try {
        if (typeof html2canvas === 'undefined') { window.location.href = url; return; }
        const cap = await gmCaptureBody();
        const overlay = gmMakeOverlay(cap.w, cap.h);
        const ctx = overlay.getContext('2d');
        document.body.style.visibility = 'hidden';

        cap.particles.forEach(function (p) {
            p.vx = (Math.random() - 0.5) * 140;
            p.vSpin = (Math.random() - 0.5) * 0.3;
        });

        const start = performance.now();
        function frame(now) {
            const t = Math.min(1, (now - start) / GM_TRANSITION_DURATION);
            ctx.clearRect(0, 0, cap.w, cap.h);
            for (const p of cap.particles) {
                const px = p.x + p.vx * t;
                const py = p.y + 380 * t * t; // gravity fall
                const alpha = p.a * (1 - t);
                if (alpha <= 0.02) continue;
                ctx.fillStyle = 'rgba(' + p.r + ',' + p.g + ',' + p.b + ',' + alpha + ')';
                ctx.fillRect(px, py, p.size, p.size);
            }
            if (t < 1) requestAnimationFrame(frame);
            else { sessionStorage.setItem(GM_TRANSITION_FLAG, '1'); window.location.href = url; }
        }
        requestAnimationFrame(frame);
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
        const cap = await gmCaptureBody();

        document.body.style.visibility = 'hidden';
        const overlay = gmMakeOverlay(cap.w, cap.h);
        const ctx = overlay.getContext('2d');

        cap.particles.forEach(function (p) {
            p.sx = p.x + (Math.random() - 0.5) * 260;
            p.sy = p.y - 260 - Math.random() * 220;
        });

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
            if (t < 1) requestAnimationFrame(frame);
            else { overlay.remove(); document.body.style.visibility = 'visible'; }
        }
        requestAnimationFrame(frame);
    } catch (e) {
        document.body.style.visibility = 'visible';
    }
}

document.addEventListener('DOMContentLoaded', gmReformOnLoad);
