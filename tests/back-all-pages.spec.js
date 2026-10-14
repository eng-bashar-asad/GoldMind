// Every page's back button, and the Android hardware back (gmHardwareBack), return to the page you came from.
const { test, expect } = require('@playwright/test');
const fs = require('fs'), path = require('path');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const root = path.resolve(__dirname, '..');
const START = 'reports-ar.html';
const BACK = /onclick="(gmSmartBack|goBack|headerBack)\(/;
const pages = fs.readdirSync(root).filter(f => f.endsWith('.html') && !/_\d+\.html$|^index-ar_3|^harness/.test(f) && f !== START
  && BACK.test(fs.readFileSync(path.join(root, f), 'utf8')));
const name = p => new URL(p.url()).pathname.split('/').pop();

async function open(page, file) {
  page.on('dialog', d => d.accept().catch(() => {}));
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'محل', currency: 'USD', diamonds_enabled: true }] } });
  await page.goto('/' + START); await page.waitForTimeout(300);
  await page.goto('/' + file); await page.waitForTimeout(700);
}

for (const file of pages) test('back button: ' + file, async ({ page }) => {
  await open(page, file);
  test.skip(name(page) !== file, 'page forwarded elsewhere with test data');
  const btn = page.locator('.gm-back-btn-3d').filter({ visible: true }).first();
  test.skip(!(await btn.count()), 'back button only shown in some states');
  await btn.click();
  await expect.poll(() => name(page)).toBe(START);
});

test('hardware back steps back like the page button, and exits on home', async ({ page }) => {
  await open(page, 'diamond-inventory-list-ar.html');
  expect(name(page)).toBe('diamond-inventory-list-ar.html');
  expect(await page.evaluate(() => gmHardwareBack())).toBe('done');
  await expect.poll(() => name(page)).toBe(START);
  await page.goto('/index-ar.html'); await page.waitForTimeout(300);
  expect(await page.evaluate(() => gmHardwareBack())).toBe('exit');
});
