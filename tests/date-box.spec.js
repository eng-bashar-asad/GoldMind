// Date boxes show DD/MM/YYYY drawn by the app (not the phone's jumbled format),
// for typed, picked and code-set values; the value itself stays YYYY-MM-DD.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test.use({ locale: 'ar-SY' });

test('date box shows 30/09/2026', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { realCdn: true, generic: true, db: { stores: [{ id: STORE, name: 'x', vat_rate: 0 }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/profit-report-ar.html');
  await page.waitForTimeout(1500);
  // the report sets its dates from code (this month)
  const from = await page.$eval('#date-from', el => ({ v: el.value, shown: el.__gmDateOverlay && el.__gmDateOverlay.textContent }));
  expect(from.v).toMatch(/^\d{4}-\d{2}-01$/);
  expect(from.shown).toBe(from.v.slice(8, 10) + '/' + from.v.slice(5, 7) + '/' + from.v.slice(0, 4));
  await page.fill('#date-to', '2026-09-30');
  expect(await page.$eval('#date-to', el => el.__gmDateOverlay.textContent)).toBe('30/09/2026');
  await page.$eval('#date-to', el => { el.value = ''; });
  expect(await page.$eval('#date-to', el => el.__gmDateOverlay.textContent)).toBe('يوم/شهر/سنة');
  // added later by page code
  await page.evaluate(() => { const i = document.createElement('input'); i.type = 'date'; i.id = 'late'; i.className = 'w-full h-10 border'; document.body.appendChild(i); i.value = '2026-01-05'; });
  await expect.poll(() => page.$eval('#late', el => el.__gmDateOverlay && el.__gmDateOverlay.textContent)).toBe('05/01/2026');
  expect(errs).toEqual([]);
});
