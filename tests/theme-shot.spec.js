const { test } = require('@playwright/test');
const { install } = require('./fake-backend');
test.skip(!process.env.UI_OUT, 'audit only');
for (const th of ['cosmic-steel']) for (const f of ['index-ar.html', 'new-sale-ar.html', 'accounting-check-ar.html']) test(th + ' ' + f, async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await install(page, { generic: true, realCdn: true });
  await page.addInitScript(t => { try { localStorage.setItem('goldmind_theme', t); } catch (e) {} }, th);
  await page.goto('/' + f); await page.waitForTimeout(2500);
  await page.screenshot({ path: `${process.env.UI_OUT}/${th}-${f}.png` });
});
