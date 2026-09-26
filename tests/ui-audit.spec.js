// UI audit (not part of CI): screenshots + simple accessibility counts.
const { test } = require('@playwright/test');
const { install } = require('./fake-backend');
const OUT = process.env.UI_OUT;
const PAGES = (process.env.UI_PAGES || 'index-ar.html,new-sale-ar.html,inventory-list-ar.html,invoices-list-ar.html,daily-cashbox-ar.html,customer-debts-ar.html').split(',');
test.skip(!OUT, 'audit only');
for (const f of PAGES) test('audit ' + f, async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  page.on('dialog', d => d.dismiss().catch(() => {}));
  await install(page, { generic: true, realCdn: true });
  await page.goto('/' + f); await page.waitForTimeout(3000);
  await page.screenshot({ path: `${OUT}/${f}${process.env.UI_TAG || ''}.png`, fullPage: false });
  const r = await page.evaluate(() => {
    const vis = el => { const b = el.getBoundingClientRect(); return b.width > 0 && b.height > 0 && getComputedStyle(el).visibility !== 'hidden'; };
    const btns = [...document.querySelectorAll('button, a, [role=button]')].filter(vis);
    const iconOnly = btns.filter(b => !b.textContent.replace(/[a-z_]+/g, '').trim() && !b.getAttribute('aria-label') && !b.getAttribute('title'));
    const small = btns.filter(b => { const r = b.getBoundingClientRect(); return r.width < 40 || r.height < 40; });
    const tiny = [...document.querySelectorAll('body *')].filter(e => e.childNodes.length && [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim()) && vis(e) && parseFloat(getComputedStyle(e).fontSize) < 11);
    const inputs = [...document.querySelectorAll('input:not([type=hidden]), select, textarea')].filter(vis);
    const unlabeled = inputs.filter(i => !i.labels?.length && !i.getAttribute('aria-label'));
    return { buttons: btns.length, iconOnlyNoLabel: iconOnly.length, under40px: small.length, textUnder11px: tiny.length, inputs: inputs.length, inputsNoLabel: unlabeled.length, hscroll: document.documentElement.scrollWidth > innerWidth };
  });
  console.log('AUDIT', f, JSON.stringify(r));
});
