const { test } = require('@playwright/test');
test.skip(!process.env.UI_OUT, 'audit only');
for (const f of ['login-entry-ar.html', 'company-register-ar.html', 'admin-login-ar.html']) for (const [w, h] of [[390, 844], [1280, 800]]) test(`${f} ${w}`, async ({ page }) => {
  await page.setViewportSize({ width: w, height: h });
  await page.route(/cdn\.jsdelivr\.net\/npm\/@supabase/, r => r.fulfill({ contentType: 'text/javascript', body: require('fs').readFileSync(require.resolve('@supabase/supabase-js/dist/umd/supabase.js'), 'utf8') }));
  await page.route(/\.supabase\.co\//, r => r.fulfill({ json: {} }));
  await page.goto('/' + f); await page.waitForTimeout(2500);
  await page.screenshot({ path: `${process.env.UI_OUT}/login-${f}-${w}.png` });
  const r = await page.evaluate(() => {
    const vis = el => { const b = el.getBoundingClientRect(); return b.width > 0 && b.height > 0; };
    return { inputs: [...document.querySelectorAll('input')].filter(vis).map(i => `${i.type}|label:${!!(i.labels && i.labels.length)}|ac:${i.autocomplete}|h:${Math.round(i.getBoundingClientRect().height)}`), buttons: [...document.querySelectorAll('button')].filter(vis).map(b => `${Math.round(b.getBoundingClientRect().height)}:${b.textContent.trim().slice(0, 20)}`) };
  });
  console.log('LOGIN', f, w, JSON.stringify(r));
});
