// Phone home header (Bashar 2026-11-02): with a status bar on top and a long greeting line,
// the header grows below the status bar and its buttons stay fully on screen.
const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

test('header clears the status bar and keeps its buttons on screen', async ({ page }) => {
  await install(page, { generic: true });
  await page.setViewportSize({ width: 360, height: 780 });
  await page.goto('/index-ar.html');
  await page.addStyleTag({ content: ':root{--safe-area-inset-top:32px!important}' }); // a phone status bar
  await page.evaluate(() => { document.getElementById('mobGreetSub').textContent = 'الاثنين، 2 نوفمبر · Ahmad Al Khayat Sharjah — فرع الشارقة الرئيسي'; });
  const h = await page.locator('header.fixed.top-0').first().boundingBox();
  const rem = await page.evaluate(() => parseFloat(getComputedStyle(document.documentElement).fontSize));
  expect(h.height).toBeGreaterThanOrEqual(4 * rem + 32 - 1);
  for (const id of ['#currency-toggle-btn', '#quick-search-btn', '#moves-btn']) {
    const b = await page.locator(id).boundingBox();
    expect(b.x).toBeGreaterThanOrEqual(0);
    expect(b.y).toBeGreaterThanOrEqual(32);
  }
});
