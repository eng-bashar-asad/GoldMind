// zebra-rfid.js — GoldMind
// Shared helper for RFID label printing on Zebra desktop printers
// (ZD220/ZD230/ZD888 class) via the Zebra Browser Print local agent.
//
// Scope on purpose:
//  - EPC <-> hex helpers (Zebra RFID commands need the EPC as raw hex)
//  - ZPL builders for a barcode-only label and a barcode+RFID-encode label
//  - Discovery + send via BrowserPrint (window.BrowserPrint)
//
// IMPORTANT: window.BrowserPrint is NOT injected automatically just
// because the Zebra Browser Print desktop app is installed and running.
// That app only runs a local HTTP agent (127.0.0.1:9100, or :9101 over
// HTTPS) that the BROWSER PRINT JS BRIDGE talks to -- the bridge script
// itself must still be loaded by the page like any other library. Zebra
// doesn't publish it on an official CDN (only as a manual download from
// their developer portal), but the same file is mirrored on jsDelivr as
// the npm package "zebra-browser-print-min". Every page that calls
// GMZebra.isAvailable()/print*() must load it BEFORE this file -- and
// MUST reference the exact minified filename, not just the package
// directory: jsDelivr serves an HTML landing page (not the JS) for a
// bare "…/zebra-browser-print-min@3.0.216/" URL with no filename, which
// a <script> tag then silently fails to execute as JS. This bit
// GoldMind once already -- confirm any URL change actually returns
// Content-Type: application/javascript (curl -I) before relying on it.
//   <script src="https://cdn.jsdelivr.net/npm/zebra-browser-print-min@3.0.216/BrowserPrint-3.0.216.min.js"></script>
//   <script src="zebra-rfid.js"></script>
// Skipping that script tag is exactly why isAvailable() will always
// return false and printing will always show the "not installed" error,
// even with the desktop agent correctly installed and a printer set as
// default in its own settings window -- this bit GoldMind once already.
//
// This file intentionally has zero UI. Pages call GMZebra.* and render
// their own status/errors.

var GMZebra = (function () {
  'use strict';

  // ---- EPC <-> hex -------------------------------------------------
  // Zebra RFID tags are programmed with a raw hex payload. We encode a
  // plain ASCII identifier (e.g. the piece barcode) into hex so it can
  // be written with ^RFW,H and read back the same way with ^RFR,H.
  function asciiToHex(str) {
    var out = '';
    for (var i = 0; i < str.length; i++) {
      var h = str.charCodeAt(i).toString(16).toUpperCase();
      if (h.length < 2) h = '0' + h;
      out += h;
    }
    return out;
  }

  function hexToAscii(hex) {
    hex = (hex || '').replace(/\s+/g, '');
    var out = '';
    for (var i = 0; i < hex.length; i += 2) {
      var code = parseInt(hex.substr(i, 2), 16);
      if (!isNaN(code) && code > 0) out += String.fromCharCode(code);
    }
    return out;
  }

  // EPC memory bank is word-aligned (2 bytes/word). Pad the hex payload
  // to an even number of bytes so the tag firmware doesn't reject it.
  function padEvenBytes(hex) {
    return (hex.length % 4 === 0) ? hex : hex + '0'.repeat(4 - (hex.length % 4));
  }

  // Build a fresh, short, printable EPC source string for a piece.
  // Kept short on purpose (EPC tags are commonly 96-bit / 24 hex chars) —
  // GoldMind uses its own barcode as the human-readable id and only needs
  // the EPC to resolve back to that same barcode on scan.
  function buildEpcSource(barcode, storeShortId) {
    var raw = (storeShortId ? storeShortId + '-' : '') + (barcode || '');
    return raw.slice(0, 24); // stays within a 96-bit tag's usable ASCII length
  }

  // ---- ZPL builders --------------------------------------------------
  // Barcode-only label (no RFID programming) — used when rfid_enabled is
  // off for the store, or as a plain reprint. widthDots/heightDots (Zebra
  // dot units = mm * dpi / 25.4) are optional -- callers resolve them
  // from the store's configured label size; the original hardcoded
  // 406x203 (roughly 50mm x 25mm at 203dpi) is the fallback so existing
  // callers that don't pass them keep working unchanged. Content
  // vertical positions scale proportionally to the configured height so
  // other label sizes don't get cut off or float in empty space.
  function buildBarcodeZPL(opts) {
    opts = opts || {};
    var storeName = escapeZpl(opts.storeName || 'GoldMind');
    var line1 = escapeZpl(opts.line1 || '');
    var line2 = escapeZpl(opts.line2 || '');
    var barcode = escapeZpl(opts.barcode || '');
    var w = opts.widthDots || 406;
    var h = opts.heightDots || 203;
    var scale = h / 203;
    var y1 = Math.round(8 * scale), y2 = Math.round(32 * scale), y3 = Math.round(54 * scale), y4 = Math.round(78 * scale);
    var barHeight = Math.max(30, Math.round(60 * scale));
    // Shifts every field left/right together. Positive = right, negative =
    // left. Clamped so content can't be pushed off either edge of the label.
    var x = Math.max(0, Math.min(w - 10, 10 + (opts.xOffsetDots || 0)));
    return '^XA' +
      '^PW' + w + '^LL' + h +
      '^FO' + x + ',' + y1 + '^A0N,20,20^FD' + storeName + '^FS' +
      '^FO' + x + ',' + y2 + '^A0N,18,18^FD' + line1 + '^FS' +
      '^FO' + x + ',' + y3 + '^A0N,16,16^FD' + line2 + '^FS' +
      '^FO' + x + ',' + y4 + '^BY2' +
      '^BCN,' + barHeight + ',Y,N,N' +
      '^FD' + barcode + '^FS' +
      '^XZ';
  }

  // mm (and DPI) -> Zebra dots. 1 inch = 25.4mm.
  function mmToDots(mm, dpi) {
    return Math.round((mm || 0) * (dpi || 203) / 25.4);
  }

  // Barcode label + RFID tag programming in the same pass.
  // ^RS8 selects the RFID module; ^RFW,H writes the hex payload to the
  // EPC memory bank; ^RFR,H right after (optional) re-reads to verify.
  function buildRfidEncodeZPL(opts) {
    opts = opts || {};
    var base = buildBarcodeZPL(opts);
    var epcHex = padEvenBytes((opts.epcHex || '').toUpperCase());
    // splice the RFID block in right after ^XA
    var rfidBlock = '^RS8' +
      '^RFW,H^FD' + epcHex + '^FS';
    return base.replace('^XA', '^XA' + rfidBlock);
  }

  function escapeZpl(str) {
    return String(str == null ? '' : str).replace(/\^/g, ' ').replace(/~/g, ' ');
  }

  // ---- Browser Print integration -------------------------------------
  // Requires (1) the Zebra Browser Print desktop app running locally, AND
  // (2) the calling page having actually loaded the BrowserPrint JS bridge
  // script (see the file header) -- window.BrowserPrint only exists once
  // both are true.
  function isAvailable() {
    return typeof window !== 'undefined' && !!window.BrowserPrint;
  }

  function getDefaultPrinter() {
    return new Promise(function (resolve, reject) {
      if (!isAvailable()) { reject(new Error('Zebra Browser Print غير مثبّت أو غير متاح على هذا الجهاز.')); return; }
      window.BrowserPrint.getDefaultDevice('printer', function (device) {
        if (!device) { reject(new Error('لم يتم العثور على طابعة Zebra افتراضية.')); return; }
        resolve(device);
      }, function (err) {
        reject(new Error('تعذّر الاتصال بطابعة Zebra: ' + err));
      });
    });
  }

  function sendZpl(zpl) {
    return getDefaultPrinter().then(function (device) {
      return new Promise(function (resolve, reject) {
        device.send(zpl, function () {
          resolve(true);
        }, function (err) {
          reject(new Error('فشل إرسال البيانات للطابعة: ' + err));
        });
      });
    });
  }

  // High-level: print a barcode-only label.
  function printBarcodeLabel(opts) {
    return sendZpl(buildBarcodeZPL(opts));
  }

  // High-level: print + program the RFID tag in one label pass.
  function printAndEncodeRfid(opts) {
    return sendZpl(buildRfidEncodeZPL(opts));
  }

  return {
    asciiToHex: asciiToHex,
    hexToAscii: hexToAscii,
    padEvenBytes: padEvenBytes,
    buildEpcSource: buildEpcSource,
    buildBarcodeZPL: buildBarcodeZPL,
    buildRfidEncodeZPL: buildRfidEncodeZPL,
    mmToDots: mmToDots,
    isAvailable: isAvailable,
    getDefaultPrinter: getDefaultPrinter,
    sendZpl: sendZpl,
    printBarcodeLabel: printBarcodeLabel,
    printAndEncodeRfid: printAndEncodeRfid
  };
})();
