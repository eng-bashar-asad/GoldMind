// Every "take photo" input offers camera or a picture from the device.
const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

async function setup(page) {
  await install(page, {});
  await page.goto('/tests/harness.html');
  await page.evaluate(() => {
    document.body.insertAdjacentHTML('beforeend',
      '<input type="file" accept="image/*" capture="environment" id="cam" style="display:none">' +
      '<button id="btn" onclick="document.getElementById(\'cam\').click()">صورة</button>');
  });
}

test('gallery choice opens the file picker without forcing the camera', async ({ page }) => {
  await setup(page);
  await page.click('#btn');
  await expect(page.locator('#gm-photo-sheet')).toBeVisible();
  const [chooser] = await Promise.all([
    page.waitForEvent('filechooser'),
    page.click('#gm-photo-sheet button[data-src="gallery"]'),
  ]);
  expect(chooser.element()).toBeTruthy();
  expect(await page.evaluate(() => document.getElementById('cam').hasAttribute('capture'))).toBe(false);
  await page.waitForTimeout(1700);
  expect(await page.evaluate(() => document.getElementById('cam').getAttribute('capture'))).toBe('environment'); // restored
});

test('camera choice keeps the camera; cancel opens nothing', async ({ page }) => {
  await setup(page);
  await page.click('#btn');
  const [chooser] = await Promise.all([
    page.waitForEvent('filechooser'),
    page.click('#gm-photo-sheet button[data-src="camera"]'),
  ]);
  expect(await chooser.element().getAttribute('capture')).toBe('environment');
  await page.click('#btn');
  let opened = false;
  page.on('filechooser', () => { opened = true; });
  await page.click('#gm-photo-sheet button[data-src="cancel"]');
  await page.waitForTimeout(500);
  expect(opened).toBe(false);
  await expect(page.locator('#gm-photo-sheet')).toHaveCount(0);
});

test('real page: new sale stock photo asks for the source', async ({ page }) => {
  await install(page, { generic: true });
  await page.goto('/new-sale-ar.html');
  await page.evaluate(() => document.getElementById('stock-photo-input').click());
  await expect(page.locator('#gm-photo-sheet')).toContainText('اختيار صورة من الجهاز');
});
