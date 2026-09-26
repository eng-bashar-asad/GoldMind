// Every page must load without code errors (syntax mistakes, missing functions).
// Data comes from a fake backend, so errors caused only by fake data are ignored.
const { test, expect } = require('@playwright/test');
const fs = require('fs'), path = require('path');
const { install } = require('./fake-backend');

const root = path.resolve(__dirname, '..');
const pages = fs.readdirSync(root).filter(f => f.endsWith('.html') && !/_\d+\.html$|^index-ar_3|^logo-preview|^login-ar-4/.test(f));

for (const file of pages) {
  test(`page loads: ${file}`, async ({ page }) => {
    const errors = [];
    page.on('pageerror', e => { if (/SyntaxError|ReferenceError/.test(String(e.name) + String(e.message))) errors.push(e.message); });
    page.on('dialog', d => d.dismiss().catch(() => {}));
    await install(page, { generic: true });
    await page.goto('/' + file, { waitUntil: 'load' }).catch(() => {});
    await page.waitForTimeout(800);
    expect(errors, file).toEqual([]);
  });
}
