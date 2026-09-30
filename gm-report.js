// GoldMind — shared helpers for printable reports (profit report, financial report).

// ---- Day boundaries in the shop's display timezone ----
// "Today" / a chosen date must mean the shop's day (e.g. Damascus or Dubai), not UTC,
// otherwise a sale made after local midnight lands on the previous day.
function gmTzOffsetMs(t, tz) {
  var parts = {};
  new Intl.DateTimeFormat('en-US', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' })
    .formatToParts(new Date(t)).forEach(function (p) { parts[p.type] = p.value; });
  var asUTC = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour % 24, +parts.minute, +parts.second);
  return asUTC - Math.floor(t / 1000) * 1000;
}
// 'YYYY-MM-DD' -> ISO instant of that day's 00:00 in tz
function gmDayStartISO(dateStr, tz) {
  tz = tz || (typeof gmGetDisplayTimeZone === 'function' ? gmGetDisplayTimeZone() : 'UTC');
  var p = String(dateStr).split('-').map(Number);
  var guess = Date.UTC(p[0], p[1] - 1, p[2]);
  var t = guess - gmTzOffsetMs(guess, tz);
  t = guess - gmTzOffsetMs(t, tz); // second pass settles DST edges
  return new Date(t).toISOString();
}
// 'YYYY-MM-DD' of an instant, in tz
function gmDateStrInTz(t, tz) {
  tz = tz || (typeof gmGetDisplayTimeZone === 'function' ? gmGetDisplayTimeZone() : 'UTC');
  return new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(t));
}
function gmAddDays(dateStr, n) {
  var p = String(dateStr).split('-').map(Number);
  return new Date(Date.UTC(p[0], p[1] - 1, p[2] + n)).toISOString().slice(0, 10);
}
// Inclusive date range -> { from, to } instants for .gte(from).lt(to)
function gmRangeISO(fromStr, toStr) {
  return { from: gmDayStartISO(fromStr), to: gmDayStartISO(gmAddDays(toStr, 1)) };
}
// Supabase returns at most 1000 rows per request: read every page.
async function gmFetchAllRows(makeQuery) {
  var all = [];
  for (var from = 0; ; from += 1000) {
    var r = await makeQuery().range(from, from + 999);
    if (r.error) return { data: all, error: r.error };
    all = all.concat(r.data || []);
    if (!r.data || r.data.length < 1000) return { data: all, error: null };
  }
}

// ---- PDF of a report sheet ----
// Copies the sheet, drops on-screen-only controls (.no-print), shows the
// print-only header (.gm-print-only) and hands it to gmPdfFromNodes
// (supabase-config.js), which also covers the Android app's share sheet.
function gmReportNode(sheetEl) {
  var copy = sheetEl.cloneNode(true);
  copy.removeAttribute('id');
  copy.classList.remove('hidden');
  Array.prototype.forEach.call(copy.querySelectorAll('.no-print'), function (e) { e.remove(); });
  Array.prototype.forEach.call(copy.querySelectorAll('.gm-print-only'), function (e) { e.classList.remove('hidden'); e.style.display = 'block'; });
  Array.prototype.forEach.call(copy.querySelectorAll('.overflow-x-auto,.overflow-hidden'), function (e) { e.style.overflow = 'visible'; });
  copy.classList.add('gm-pdf');
  return copy;
}
async function gmReportPdf(sheetEl, filename, btn) {
  var old = btn ? btn.innerHTML : '';
  if (btn) { btn.disabled = true; btn.innerHTML = '<span class="material-symbols-outlined animate-spin">progress_activity</span>'; }
  try {
    await gmLoadScript('https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js', 'html2pdf');
    await gmPdfFromNodes([gmReportNode(sheetEl)], filename, filename);
  } catch (e) {
    alert('تعذّر إنشاء ملف PDF: ' + (e && e.message ? e.message : e));
  } finally {
    if (btn) { btn.disabled = false; btn.innerHTML = old; }
  }
}
