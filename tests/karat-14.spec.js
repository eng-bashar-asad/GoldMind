const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');
// 14K for every company (بشار 2026-11-18): the karat pickers offer it, before 18.
for (const [page_, sel] of [['inventory-add.html', 'select:has(option[value="22"])'], ['new-sale-ar.html', '#manual-karat'], ['opening-stock-ar.html', 'select:has(option[value="22"])']]) {
  test(`14K is offered on ${page_}`, async ({ page }) => {
    await install(page, { generic: true });
    await page.goto('/' + page_);
    const vals = await page.locator(sel).first().locator('option').evaluateAll(os => os.map(o => o.value).filter(v => /^\d+$/.test(v)));
    expect(vals.slice(0, 2)).toEqual(['14', '18']);
  });
}
