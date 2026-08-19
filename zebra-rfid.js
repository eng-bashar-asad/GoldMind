// zebra-rfid.js — GoldMind
// Shared helper for RFID label printing on Zebra desktop printers
// (ZD220/ZD230/ZD888 class) via the Zebra Browser Print local agent.
//
// Scope on purpose:
//  - EPC <-> hex helpers (Zebra RFID commands need the EPC as raw hex)
//  - ZPL builders for a barcode-only label and a barcode+RFID-encode label
//  - Discovery + send via BrowserPrint (window.BrowserPrint, injected by
//    the Zebra Browser Print SDK the user installs locally — NOT loaded
//    from a CDN, there isn't one; the desktop agent injects it)
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
  // off for the store, or as a plain reprint.
  function buildBarcodeZPL(opts) {
    opts = opts || {};
    var storeName = escapeZpl(opts.storeName || 'GoldMind');
    var line1 = escapeZpl(opts.line1 || '');
    var line2 = escapeZpl(opts.line2 || '');
    var barcode = escapeZpl(opts.barcode || '');
    return '^XA' +
      '^PW406^LL203' +
      '^FO10,8^A0N,20,20^FD' + storeName + '^FS' +
      '^FO10,32^A0N,18,18^FD' + line1 + '^FS' +
      '^FO10,54^A0N,16,16^FD' + line2 + '^FS' +
      '^FO10,78^BY2' +
      '^BCN,60,Y,N,N' +
      '^FD' + barcode + '^FS' +
      '^XZ';
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
  // Requires the Zebra Browser Print desktop app/SDK running locally
  // (injects window.BrowserPrint). We never load it from a CDN — Zebra
  // doesn't publish one; it must be installed by the user and the page
  // loads it from the local agent at http://127.0.0.1:9100 under the hood.
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
    isAvailable: isAvailable,
    getDefaultPrinter: getDefaultPrinter,
    sendZpl: sendZpl,
    printBarcodeLabel: printBarcodeLabel,
    printAndEncodeRfid: printAndEncodeRfid
  };
})();
