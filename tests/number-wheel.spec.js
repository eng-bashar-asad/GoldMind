// Number boxes: mouse wheel over a focused box never changes the number; no spin arrows.
const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

test('wheel does not change a focused number box', async ({ page }) => {
  await install(page, { generic: true, db: {} });
  await page.goto('/login-entry-ar.html');
  await page.evaluate(() => { const i = document.createElement('input'); i.type = 'number'; i.id = 'n'; i.value = '100'; document.body.prepend(i); });
  await page.focus('#n');
  const box = await page.locator('#n').boundingBox();
  await page.mouse.move(box.x + 5, box.y + 5);
  await page.mouse.wheel(0, -200);
  await page.mouse.wheel(0, -200);
  await expect(page.locator('#n')).toHaveValue('100');
  expect(await page.evaluate(() => document.activeElement.id)).not.toBe('n');
  expect(await page.evaluate(() => getComputedStyle(document.getElementById('n')).appearance)).toBe('textfield');
});
