const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');
// On the computer the piece photo opens as a square about half the screen, not full screen (بشار 2026-11-18).
test('piece photo viewer: square, about half the screen, on the computer', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await install(page, { generic: true });
  await page.goto('/inventory-list-ar.html');
  await page.evaluate(() => openPhotoLightbox('data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="800" height="400"/>'));
  const b = await page.locator('#lightbox-img').boundingBox();
  expect(Math.round(b.width)).toBe(Math.round(b.height));
  expect(b.width).toBeLessThanOrEqual(720);
  expect(b.width).toBeGreaterThan(400);
});
