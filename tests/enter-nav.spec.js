// Enter moves to the next field on every screen (gm-nav.js gmEnterNext); Shift+Enter goes back;
// the last field presses the save button; barcode boxes keep their own Enter.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('Enter walks the fields, skips hidden/disabled ones, saves on the last; barcode boxes are left alone', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  await page.goto('/expense-entry-ar.html');
  await page.waitForFunction(() => typeof window.gmEnterNext === 'function');
  await page.evaluate(() => {
    const s = document.createElement('section');
    s.id = 'enterTest';
    s.innerHTML = '<input id="a"><input id="h" class="hidden"><input id="d" disabled><select id="b"><option>1</option></select>'
      + '<input id="c" type="number"><input id="bc" placeholder="باركود القطعة"><button id="sv" onclick="window.__saved=(window.__saved||0)+1">حفظ</button>';
    document.body.prepend(s);
  });
  await page.focus('#a');
  await page.keyboard.press('Enter');
  await expect(page.locator('#b')).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.locator('#c')).toBeFocused();
  await page.keyboard.press('Shift+Enter');
  await expect(page.locator('#b')).toBeFocused();
  await page.focus('#bc');
  await page.keyboard.press('Enter');
  await expect(page.locator('#bc')).toBeFocused(); // barcode box: untouched
  expect(await page.evaluate(() => window.__saved || 0)).toBe(0);
  await page.evaluate(() => document.getElementById('bc').remove());
  await page.focus('#c');
  await page.keyboard.press('Enter'); // last field -> save
  expect(await page.evaluate(() => window.__saved || 0)).toBe(1);
});
