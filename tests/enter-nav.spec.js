// Enter moves to the next field on every screen (gm-nav.js gmEnterNext); Shift+Enter goes back;
// Enter never presses a button (last field: nothing); barcode boxes keep their own Enter; cards don't stop it.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('Enter walks the fields, skips hidden/disabled ones, never saves; barcode boxes are left alone', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  await page.goto('/expense-entry-ar.html');
  await page.waitForFunction(() => typeof window.gmEnterNext === 'function');
  await page.evaluate(() => {
    const s = document.createElement('section');
    s.id = 'enterTest'; s.setAttribute('data-enter-scope', '');
    s.innerHTML = '<input id="a"><input id="h" style="display:none"><input id="d" disabled><select id="b"><option>1</option></select>'
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
  await page.keyboard.press('Enter'); // last field: stays, nothing pressed
  await expect(page.locator('#c')).toBeFocused();
  expect(await page.evaluate(() => window.__saved || 0)).toBe(0);
  // two separate cards: Enter goes on from the first card into the second
  await page.evaluate(() => {
    const w = document.createElement('div');
    w.innerHTML = '<section class="gm-card"><input id="x1"></section><div class="gm-card"><input id="x2"></div>';
    document.body.prepend(w);
  });
  await page.focus('#x1');
  await page.keyboard.press('Enter');
  await expect(page.locator('#x2')).toBeFocused();
});
