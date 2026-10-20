// Phones: the date box shows the chosen date once (Android drew it twice on top of itself in RTL).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const db = () => ({ stores: [{ id: STORE, name: 'x', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], daily_cash_log: [] });

test.describe('touch screen', () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  test('the date is written once as DD/MM/YYYY and follows changes made by the page', async ({ page }) => {
    await install(page, { db: db() });
    await page.goto('/daily-cashbox-ar.html');
    await page.evaluate(() => toggleRangePanel());
    const inp = page.locator('#rangeFromInput');
    await expect(inp).toHaveClass(/\bgm-date-masked\b/);
    await page.evaluate(() => { document.getElementById('rangeFromInput').value = '2026-10-17'; });
    await expect(page.locator('#rangeFromInput + .gm-date-txt')).toHaveText('17/10/2026');
    expect(await inp.inputValue()).toBe('2026-10-17');               // the real value is untouched
    await inp.fill('2026-09-23');
    await expect(page.locator('#rangeFromInput + .gm-date-txt')).toHaveText('23/09/2026');
  });
});

test('computer: date boxes stay native', async ({ page }) => {
  await install(page, { db: db() });
  await page.goto('/daily-cashbox-ar.html');
  await expect(page.locator('#rangeFromInput')).not.toHaveClass(/\bgm-date-masked\b/);
});
