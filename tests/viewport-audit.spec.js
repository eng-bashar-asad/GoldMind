// Not part of CI: no page may scroll sideways on phone, landscape or tablet.
const { test, expect } = require('@playwright/test');
const fs = require('fs'), path = require('path');
const { install } = require('./fake-backend');
test.skip(!process.env.UI_OUT, 'audit only');
const root = path.resolve(__dirname, '..');
const pages = fs.readdirSync(root).filter(f => f.endsWith('-ar.html') && !/_\d+\.html$|index-ar_3|print|label|receipt|certificate/.test(f));
const sizes = [[375, 812], [812, 375], [768, 1024]];
for (const f of pages) test('no sideways scroll: ' + f, async ({ page }) => {
  page.on('dialog', d => d.dismiss().catch(() => {}));
  await install(page, { generic: true, realCdn: true });
  const bad = [];
  for (const [w, h] of sizes) {
    await page.setViewportSize({ width: w, height: h });
    await page.goto('/' + f).catch(() => {}); await page.waitForTimeout(1500);
    const over = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    if (over > 2) bad.push(`${w}x${h}: +${over}px`);
  }
  expect(bad, f).toEqual([]);
});
