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
    var y1 = Math.round(8 * scale), y2 = Math.round(38 * scale), y3 = Math.round(60 * scale), y4 = Math.round(84 * scale);
    // Bar height is its own explicit setting (mm -> dots, same as the
    // label's own width/height). Floor is just "not literally zero" --
    // an earlier floor of 20 silently overrode small intentional values
    // like 1mm (~8 dots), which is exactly the bug that prompted this.
    var barHeight = Math.max(5, opts.barHeightDots != null ? opts.barHeightDots : Math.round(40 * scale));
    var x = Math.max(0, Math.min(w - 10, 10 + (opts.xOffsetDots || 0)));
    // ^POI inverts the WHOLE label 180 degrees as one unit -- text and
    // barcode together, from the same ^FO coordinates -- instead of
    // rotating each field individually (error-prone) or relying on an
    // external Windows-driver-level rotation (which only flips the
    // barcode's symmetric-looking bars correctly but garbles the text,
    // since the driver has no idea those glyphs need to flip too).
    var invert = opts.rotate180 ? '^POI' : '';
    var darkness = opts.darkness != null ? '^MD' + opts.darkness : '';
    var moduleWidth = opts.moduleWidth != null ? opts.moduleWidth : 2;
    return '^XA' + invert + darkness +
      '^PW' + w + '^LL' + h +
      '^FO' + x + ',' + y1 + '^A0N,20,20^FD' + storeName + '^FS' +
      '^FO' + x + ',' + y2 + '^A0N,22,22^FD' + line1 + '^FS' +
      '^FO' + x + ',' + y3 + '^A0N,16,16^FD' + line2 + '^FS' +
      '^FO' + x + ',' + y4 + '^BY' + moduleWidth +
      '^BCN,' + barHeight + ',Y,N,N' +
      '^FD' + barcode + '^FS' +
      '^XZ';
  }

  // mm (and DPI) -> Zebra dots. 1 inch = 25.4mm.
  function mmToDots(mm, dpi) {
    return Math.round((mm || 0) * (dpi || 203) / 25.4);
  }

  // Flexible field-based label builder, backing the Zebra Label Designer
  // (zebra-label-designer-ar.html): each store configures its OWN list of
  // fields (content type + column + order + font size) in
  // zebra_label_fields, instead of a fixed hardcoded layout. Two columns,
  // each field stacks under the previous one in its column; a
  // 'barcode_graphic' field reserves extra height for the bars plus
  // Zebra's own auto-printed interpretation line below them.
  function buildBarcodeZPLFromFields(opts) {
    opts = opts || {};
    var fields = opts.fields || [];
    var values = opts.values || {};
    var w = opts.widthDots || 406;
    var h = opts.heightDots || 203;
    var scale = h / 203;
    var barHeight = Math.max(5, opts.barHeightDots != null ? opts.barHeightDots : Math.round(40 * scale));
    var xBase = Math.max(0, Math.min(w - 10, 10 + (opts.xOffsetDots || 0)));
    var yStart = Math.max(0, Math.min(h - 10, Math.round(8 * scale) + (opts.yOffsetDots || 0)));
    var colWidth = Math.round((w - xBase) / 2);
    // Gap between one field and the next in the same column. Used to be a
    // fixed 6 dots -- now its own setting so lines can be pulled tighter
    // (or spread further apart) without touching anything in Windows,
    // since Browser Print sends raw ZPL straight to the printer and never
    // goes through the Windows printer driver at all.
    var margin = opts.spacingDots != null ? opts.spacingDots : Math.round(6 * scale);
    // ^BCN's "show interpretation line" flag used to be hardcoded on,
    // printing the number under the bars even when the user never added
    // "رقم الباركود" as its own field -- now it only shows if that field
    // is actually present, so the field list is the one place controlling
    // what's on the label.
    // Zebra's own auto-printed "interpretation line" under the bars used
    // to be tied to whether a barcode_number field existed ANYWHERE in
    // the list -- but a standalone barcode_number field (positioned
    // wherever the user wants) still counted, so having one meant the
    // number printed BOTH from that field AND again automatically under
    // the bars. Now the interpretation line is always off; the
    // barcode_number field (if added) is the only way the number shows,
    // positioned exactly where its row/column says.
    var moduleWidth = opts.moduleWidth != null ? opts.moduleWidth : 2;

    function textFor(field) {
      switch (field.content_type) {
        case 'barcode_number': return values.barcode || '';
        case 'company_name': return values.storeName || '';
        case 'weight': return 'W:' + (values.weight != null ? values.weight : '');
        case 'karat': return 'K' + (values.karat || '');
        case 'mc': return 'MC:' + (values.mc != null ? values.mc : '');
        case 'description': return values.description || '';
        case 'custom_text': return field.custom_text || '';
        default: return '';
      }
    }

    var body = '';
    [1, 2].forEach(function (colNum) {
      var colX = colNum === 1 ? xBase : xBase + colWidth;
      var y = yStart;
      fields
        .filter(function (f) { return f.column_num === colNum; })
        .sort(function (a, b) { return a.row_order - b.row_order; })
        .forEach(function (f) {
          if (f.content_type === 'barcode_graphic') {
            body += '^FO' + colX + ',' + y + '^BY' + moduleWidth +
              '^BCN,' + barHeight + ',' + (showBarcodeNumber ? 'Y' : 'N') + ',N,N' +
              '^FD' + escapeZpl(values.barcode || '') + '^FS';
            y += barHeight + margin + (showBarcodeNumber ? Math.round(16 * scale) : 0);
          } else {
            var fontSize = f.font_size || 20;
            var txt = escapeZpl(textFor(f));
            body += '^FO' + colX + ',' + y + '^A0N,' + fontSize + ',' + fontSize + '^FD' + txt + '^FS';
            y += fontSize + margin;
          }
        });
    });

    var invert = opts.rotate180 ? '^POI' : '';
    var darkness = opts.darkness != null ? '^MD' + opts.darkness : '';
    return '^XA' + invert + darkness + '^PW' + w + '^LL' + h + body + '^XZ';
  }

  // Barcode label + RFID tag programming in the same pass.
  // ^RS8 selects the RFID module; ^RFW,H writes the hex payload to the
  // EPC memory bank; ^RFR,H right after (optional) re-reads to verify.
  function buildRfidEncodeZPL(opts) {
    opts = opts || {};
    var base = (opts.fields && opts.fields.length) ? buildBarcodeZPLFromFields(opts) : buildBarcodeZPL(opts);
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
    opts = opts || {};
    var zpl = (opts.fields && opts.fields.length) ? buildBarcodeZPLFromFields(opts) : buildBarcodeZPL(opts);
    return sendZpl(zpl);
  }

  // High-level: print + program the RFID tag in one label pass.
  function printAndEncodeRfid(opts) {
    return sendZpl(buildRfidEncodeZPL(opts));
  }

  // Zebra printers keep their OWN persistent orientation setting in the
  // printer's memory (the "zpl.label_orientation" SGD variable) --
  // separate from both the Windows driver's rotation option AND our
  // per-label ^PO command. If that ever gets set to "inverted" (e.g. from
  // an earlier driver-level rotation attempt), it can combine with our
  // ^POI to cancel out or otherwise make rotation look like it's doing
  // nothing no matter what's toggled in GoldMind or in Windows. This
  // clears that printer-side setting back to normal so ^POI (the
  // "rotate 180" store setting) is the ONLY thing controlling rotation.
  function resetPrinterOrientation() {
    return sendZpl('! U1 setvar "zpl.label_orientation" "normal"\r\n');
  }

  return {
    asciiToHex: asciiToHex,
    hexToAscii: hexToAscii,
    padEvenBytes: padEvenBytes,
    buildEpcSource: buildEpcSource,
    buildBarcodeZPL: buildBarcodeZPL,
    buildBarcodeZPLFromFields: buildBarcodeZPLFromFields,
    buildRfidEncodeZPL: buildRfidEncodeZPL,
    mmToDots: mmToDots,
    isAvailable: isAvailable,
    getDefaultPrinter: getDefaultPrinter,
    sendZpl: sendZpl,
    printBarcodeLabel: printBarcodeLabel,
    printAndEncodeRfid: printAndEncodeRfid,
    resetPrinterOrientation: resetPrinterOrientation
  };
})();
