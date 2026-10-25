// Numbers are always entered in English digits: Arabic-Indic / Persian digits typed or pasted
// anywhere become 0-9 (and ٫ ٬ become . ,).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('Arabic digits typed or pasted into any field become English digits', async ({ page }) => {
  await install(page, { db: { stores: [{ id: STORE, name: 'محل', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.goto('/customers-ar.html');
  await page.waitForFunction(() => typeof gmLatinDigits === 'function');
  await page.evaluate(() => {
    document.body.insertAdjacentHTML('beforeend', '<input id="tn" type="number" step="0.01"><input id="tt" type="text"><textarea id="ta"></textarea>');
  });
  await page.locator('#tn').focus();
  await page.keyboard.insertText('١٢٫٥');
  await expect(page.locator('#tn')).toHaveValue('12.5');
  await page.locator('#tt').focus();
  await page.keyboard.insertText('هاتف ٠٥٠١٢٣');
  await expect(page.locator('#tt')).toHaveValue('هاتف 050123');
  await page.locator('#ta').fill('وزن ۳٫۲۵ غ');           // like a paste / autofill
  await expect(page.locator('#ta')).toHaveValue('وزن 3.25 غ');
});
