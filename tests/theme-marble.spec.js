// «الرخام الأسود» theme (بشار 2026-11-16): black marble canvas, charcoal cards with a thin gold frame, light words.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('black marble theme: picker offers it; canvas, framed dark cards, readable words; switching away clears it', async ({ page }) => {
  await install(page, { generic: true, realCdn: true, db: { stores: [{ id: STORE, name: 'محل', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], traders: [{ id: 't0', store_id: STORE, name: 'هادي' }] } });
  await page.goto('/theme-picker-ar.html');
  await expect(page.locator('body')).toContainText('الرخام الأسود');
  await page.evaluate(() => goldmindApplyTheme('black-marble'));
  await page.goto('/ledger-ar.html?trader=t0');
  const s = await page.evaluate(() => {
    const card = document.getElementById('trader-detail-card') || document.querySelector('.rounded-xl.bg-surface-container-lowest');
    return { body: getComputedStyle(document.body).backgroundImage, frame: getComputedStyle(card).borderTopColor,
      word: getComputedStyle(document.querySelector('.text-on-surface') || card).color, ink: getComputedStyle(document.documentElement).getPropertyValue('--gmi-g2').trim() };
  });
  expect(s.body).toContain('theme-black-marble.jpg');
  expect(s.frame).toBe('rgba(212, 175, 55, 0.3)');
  expect(s.word).toBe('rgb(238, 231, 214)');
  expect(s.ink).toBe('#4CD3A2');
  await page.evaluate(() => goldmindApplyTheme('warm-ingot'));
  expect(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--gmi-g2').trim())).toBe(''); // its brighter inks are gone
});
