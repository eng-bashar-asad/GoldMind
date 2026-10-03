// One date format everywhere: 27/09/2026 01:16 م, left-to-right isolated; date boxes read LTR.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
// The shop has no saved time zone, so dates follow the device's: pin it (CI runs in UTC).
test.use({ timezoneId: 'Asia/Dubai' });

test('dates: one clear format and date boxes read left to right', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.goto('/customers-ar.html');
  const r = await page.evaluate(() => ({
    full: gmFormatDateTime('2026-09-27T10:16:34Z'),
    date: gmFormatDateTime('2026-09-27T10:16:34Z', { day: '2-digit', month: '2-digit', year: 'numeric' }),
    named: gmFormatDateTime('2026-09-27T10:16:34Z', { day: 'numeric', month: 'short', year: 'numeric' }),
    time: gmFormatDateTime('2026-09-27T20:05:00Z', { hour: '2-digit', minute: '2-digit' }),
    now: gmFormatDateTime().length > 5,
    tz: gmGetDisplayTimeZone()
  }));
  const strip = v => v.replace(/[⁦⁩]/g, '');
  expect(r.tz).toBe('Asia/Dubai');
  expect(strip(r.full)).toBe('27/09/2026 02:16 م');
  expect(strip(r.date)).toBe('27/09/2026');
  expect(strip(r.named)).toBe('27/09/2026');
  expect(strip(r.time)).toBe('12:05 ص');
  expect(r.full.startsWith('⁦')).toBe(true);
  expect(r.now).toBe(true);
  await page.evaluate(() => { const i = document.createElement('input'); i.type = 'date'; i.id = 'dd'; document.body.appendChild(i); });
  expect(await page.$eval('#dd', el => getComputedStyle(el).direction)).toBe('ltr');
  // an amount shows only its own currency, even with a second currency saved
  expect(await page.evaluate(() => gmFormatDualCurrency(4500, { currency: 'USD', secondary_currency: 'SYP', secondary_currency_rate: 13000 })))
    .toBe('4,500 USD');
});
