// gm-camera.js — GoldMind
// Shared helper for capturing a piece photo from a LIVE desktop webcam.
//
// Context: photo inputs across the app already use
// <input type="file" accept="image/*" capture="environment">. On a phone
// that attribute opens the rear camera directly — but browsers ignore
// `capture` entirely on desktop, so a computer with a webcam plugged in
// only ever gets a plain "choose a file from disk" dialog. This module
// adds the missing piece: a live camera preview + snapshot button, used
// wherever a desktop webcam is actually available, with the existing file
// picker kept as the fallback (no camera detected, permission refused,
// mobile browser, etc.) — callers don't need to branch on that, GMCamera
// does it internally and simply resolves(null) when a live capture isn't
// possible so the caller can fall back to its own file input unchanged.
//
// Scope on purpose: this file only produces a File the caller can treat
// exactly like a manually-picked file (same object shape, same place in
// the existing upload code) — it never touches Supabase, storage, or any
// page-specific DOM outside the overlay it builds for itself.

var GMCamera = (function () {
  'use strict';

  function isSupported() {
    return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
  }

  // Opens a full-screen live-camera overlay and resolves with a single
  // captured frame as a File (image/jpeg), or null if the person cancels,
  // taps "اختيار من الملفات", or the camera can't be opened at all
  // (no device, permission denied, already in use by another app, ...).
  // Never rejects — a failed camera is just treated as "use the fallback".
  function capture() {
    return new Promise(function (resolve) {
      if (!isSupported()) { resolve(null); return; }

      var stream = null;
      var settled = false;

      function finish(result) {
        if (settled) return;
        settled = true;
        if (stream) { stream.getTracks().forEach(function (t) { t.stop(); }); }
        if (overlay && overlay.parentNode) { overlay.parentNode.removeChild(overlay); }
        document.removeEventListener('keydown', onKeydown, true);
        resolve(result);
      }

      function onKeydown(e) { if (e.key === 'Escape') finish(null); }
      document.addEventListener('keydown', onKeydown, true);

      var overlay = document.createElement('div');
      overlay.setAttribute('dir', 'rtl');
      overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483000;background:#0b0b0cf2;' +
        'display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;padding:20px;';

      var frame = document.createElement('div');
      frame.style.cssText = 'position:relative;width:min(92vw,560px);aspect-ratio:1/1;border-radius:16px;' +
        'overflow:hidden;background:#000;box-shadow:0 20px 50px rgba(0,0,0,.5);';

      var video = document.createElement('video');
      video.autoplay = true; video.playsInline = true; video.muted = true;
      video.style.cssText = 'width:100%;height:100%;object-fit:cover;transform:scaleX(-1);';

      var hint = document.createElement('p');
      hint.textContent = 'جارِ فتح الكاميرا...';
      hint.style.cssText = 'position:absolute;inset:0;margin:0;display:flex;align-items:center;justify-content:center;' +
        'color:#e8e8ea;font-family:inherit;font-size:13px;';

      frame.appendChild(video);
      frame.appendChild(hint);

      var controls = document.createElement('div');
      controls.style.cssText = 'display:flex;align-items:center;gap:28px;';

      var cancelBtn = document.createElement('button');
      cancelBtn.type = 'button';
      cancelBtn.setAttribute('aria-label', 'إلغاء');
      cancelBtn.textContent = '✕';
      cancelBtn.style.cssText = 'width:44px;height:44px;border-radius:999px;border:none;background:#ffffff22;' +
        'color:#fff;font-size:18px;cursor:pointer;';

      var shutterBtn = document.createElement('button');
      shutterBtn.type = 'button';
      shutterBtn.setAttribute('aria-label', 'التقط الصورة');
      shutterBtn.style.cssText = 'width:68px;height:68px;border-radius:999px;border:4px solid #fff;' +
        'background:#ffffff33;cursor:pointer;';

      var fallbackBtn = document.createElement('button');
      fallbackBtn.type = 'button';
      fallbackBtn.textContent = 'اختيار من الملفات بدلاً من الكاميرا';
      fallbackBtn.style.cssText = 'background:none;border:none;color:#cfcfd4;font-size:12px;' +
        'text-decoration:underline;cursor:pointer;font-family:inherit;';

      controls.appendChild(shutterBtn);
      controls.appendChild(cancelBtn);
      overlay.appendChild(frame);
      overlay.appendChild(controls);
      overlay.appendChild(fallbackBtn);
      document.body.appendChild(overlay);

      cancelBtn.addEventListener('click', function () { finish(null); });
      fallbackBtn.addEventListener('click', function () { finish(null); });
      overlay.addEventListener('click', function (e) { if (e.target === overlay) finish(null); });

      shutterBtn.addEventListener('click', function () {
        if (!video.videoWidth) return; // stream not actually flowing yet
        var canvas = document.createElement('canvas');
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        var ctx = canvas.getContext('2d');
        // Mirror the frame back to normal orientation on capture — the
        // preview is mirrored (::scaleX(-1)) only so it feels like a mirror
        // while framing the shot, matching every other camera UI.
        ctx.translate(canvas.width, 0);
        ctx.scale(-1, 1);
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        canvas.toBlob(function (blob) {
          if (!blob) { finish(null); return; }
          var file = new File([blob], 'piece-' + Date.now() + '.jpg', { type: 'image/jpeg' });
          finish(file);
        }, 'image/jpeg', 0.9);
      });

      navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 1280 }, height: { ideal: 1280 } }, audio: false })
        .then(function (s) {
          if (settled) { s.getTracks().forEach(function (t) { t.stop(); }); return; }
          stream = s;
          video.srcObject = s;
          hint.remove();
        })
        .catch(function () {
          // No camera, permission denied, device busy, etc. — just fall
          // back silently rather than showing a scary error the person
          // can't do anything about; the file picker link is right there.
          finish(null);
        });
    });
  }

  return { isSupported: isSupported, capture: capture };
})();


