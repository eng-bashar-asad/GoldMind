// PDF download: browser downloads as before; the Android app shares the file instead.
const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

const fakeWorker = `({ saved: null, save(n) { this.saved = n || 'default'; return Promise.resolve(); },
  outputPdf() { return Promise.resolve('data:application/pdf;filename=generated.pdf;base64,QUJD'); } })`;

test('browser: PDF is downloaded with the worker', async ({ page }) => {
  await install(page, {});
  await page.goto('/tests/harness.html');
  const saved = await page.evaluate(`(async () => { const w = ${fakeWorker}; await gmSavePdf(w, 'INV-1.pdf'); return w.saved; })()`);
  expect(saved).toBe('INV-1.pdf');
});

test('android app: PDF is written to the app and the share sheet opens', async ({ page }) => {
  await install(page, {});
  await page.addInitScript(() => {
    window.__calls = [];
    window.Capacitor = { isNativePlatform: () => true, Plugins: {
      Filesystem: {
        writeFile: async (o) => { window.__calls.push(['write', o.path, o.data, o.directory]); },
        getUri: async (o) => ({ uri: 'file:///cache/' + o.path }),
      },
      Share: { share: async (o) => { window.__calls.push(['share', o.url]); } },
    } };
  });
  await page.goto('/tests/harness.html');
  const calls = await page.evaluate(`(async () => { const w = ${fakeWorker}; await gmSavePdf(w, 'INV-2026/000001.pdf'); return { calls: window.__calls, saved: w.saved }; })()`);
  expect(calls.saved).toBeNull();
  expect(calls.calls).toEqual([
    ['write', 'INV-2026-000001.pdf', 'QUJD', 'CACHE'],
    ['share', 'file:///cache/INV-2026-000001.pdf'],
  ]);
});

test('android app: Print opens Android print service instead of doing nothing', async ({ page }) => {
  await install(page, {});
  await page.addInitScript(() => {
    window.__printed = [];
    window.Capacitor = { isNativePlatform: () => true, Plugins: {
      GMPrint: { print: async (o) => { window.__printed.push(o.name); } },
    } };
  });
  await page.goto('/tests/harness.html');
  await page.evaluate(() => { document.title = 'فاتورة INV-1'; window.print(); });
  await expect.poll(() => page.evaluate(() => window.__printed)).toEqual(['فاتورة INV-1']);
});
