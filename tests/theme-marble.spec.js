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

// بشار 2026-11-16: the brown «الملكي» theme was removed — a phone that still had it saved gets the default
test('removed brown theme: a saved choice falls back to the default theme', async ({ page }) => {
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'محل', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.addInitScript(() => localStorage.setItem('goldmind_theme', 'royal-walnut'));
  await page.goto('/theme-picker-ar.html');
  await expect(page.locator('body')).not.toContainText('الملكي');
  expect(await page.evaluate(() => [document.documentElement.getAttribute('data-gm-theme'), localStorage.getItem('goldmind_theme')])).toEqual(['warm-ingot', 'warm-ingot']);
});

// «الرخام البيج» (بشار 2026-11-16): light theme on beige marble — also in «زجاجية» mode, where the marble replaces the glass art
test('beige marble theme: picker offers it; marble canvas in normal and glass mode; white cards in a gold frame', async ({ page }) => {
  await install(page, { generic: true, realCdn: true, db: { stores: [{ id: STORE, name: 'محل', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], traders: [{ id: 't0', store_id: STORE, name: 'هادي' }] } });
  await page.goto('/theme-picker-ar.html');
  await expect(page.locator('body')).toContainText('الرخام البيج');
  await page.evaluate(() => goldmindApplyTheme('beige-marble'));
  await page.goto('/ledger-ar.html?trader=t0');
  const s = await page.evaluate(() => {
    const card = document.getElementById('trader-detail-card') || document.querySelector('.rounded-xl.bg-surface-container-lowest');
    const glass = document.documentElement.classList.contains('gm-glass');
    return { bg: getComputedStyle(glass ? document.documentElement : document.body).backgroundImage, frame: getComputedStyle(card).borderTopColor, light: document.documentElement.classList.contains('gm-light-canvas') };
  });
  expect(s.bg).toContain('theme-beige-marble.jpg');
  expect(s.frame).toBe('rgba(184, 149, 74, 0.38)');
  expect(s.light).toBe(true);
});
