// Every theme: a date box's own text stays hidden under GoldMind's DD/MM/YYYY overlay
// (beige marble's input colour showed through on Android: two dates on top of each other).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('date boxes hide their own text in every theme', async ({ page }) => {
  await install(page, { db: { stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], daily_cash_log: [] } });
  await page.goto('/daily-cashbox-range-ar.html');
  await expect(page.locator('#crFrom.gm-date-native')).toHaveCount(1);
  const themes = await page.evaluate(() => Object.keys(GOLDMIND_THEMES));
  expect(themes.length).toBeGreaterThan(3);
  for (const t of themes) {
    const c = await page.evaluate(t => { goldmindApplyTheme(t); const cs = getComputedStyle(document.getElementById('crFrom')); return [cs.color, cs.webkitTextFillColor]; }, t);
    expect(c, t).toEqual(['rgba(0, 0, 0, 0)', 'rgba(0, 0, 0, 0)']);
  }
});
