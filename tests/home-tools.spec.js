// Home «أدوات سريعة»: closed buttons; a tap opens one box, a second tap closes it.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const RATES = { USD: 1, EUR: 0.9, AED: 3.6725, SAR: 3.75, GBP: 0.78, TRY: 34, KWD: 0.31, QAR: 3.64, JOD: 0.709, EGP: 48, SYP: 13000 };
const db = () => ({
  stores: [{ id: STORE, name: 'x', currency: 'USD', country: 'SY', secondary_currency: 'SYP', secondary_currency_rate: 14000 }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 100 }, { store_id: STORE, karat: 21, price_per_gram: 116 }],
  fx_rates_daily: [],
});
async function open(page) {
  await page.setViewportSize({ width: 390, height: 900 });
  await page.route(/open\.er-api\.com/, r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ result: 'success', rates: RATES }) }));
  await install(page, { generic: true, db: db() });
  await page.goto('/index-ar.html');
  return page.locator('[data-gm-tools="m"]');
}

test('currencies: Syrian pound at the branch market rate, converter works; tap again closes', async ({ page }) => {
  const root = await open(page);
  const pill = root.locator('.gmt-pill[data-tool="fx"]');
  await pill.click();
  const panel = root.locator('[data-panel="fx"]');
  await expect(panel).toBeVisible();
  await expect(panel.locator('.gmt-rate', { hasText: 'SYP' })).toContainText('1 USD = 14,000 SYP'); // market rate, said the shop's way
  await panel.locator('[data-fx="amt"]').fill('100');
  await panel.locator('[data-fx="from"]').selectOption('USD');
  await panel.locator('[data-fx="to"]').selectOption('SYP');
  await expect(panel.locator('[data-fx="res"]')).toContainText('1,400,000 SYP');
  await pill.click();
  await expect(panel).toBeHidden();
});

test('calculator: weight × karat price + making', async ({ page }) => {
  const root = await open(page);
  await root.locator('.gmt-pill[data-tool="calc"]').click();
  const panel = root.locator('[data-panel="calc"]');
  await panel.locator('[data-c="w"]').fill('10');
  await panel.locator('[data-c="f"]').fill('15');
  await expect(panel.locator('.gmt-total b')).toHaveText('1,150.00 USD');
  await panel.locator('[data-k="21"]').click();
  await expect(panel.locator('.gmt-total b')).toHaveText('1,310.00 USD');
});

test('seasons: Syrian occasions with a countdown; opening one box closes the other', async ({ page }) => {
  const root = await open(page);
  await root.locator('.gmt-pill[data-tool="calc"]').click();
  await root.locator('.gmt-pill[data-tool="seasons"]').click();
  await expect(root.locator('[data-panel="calc"]')).toBeHidden();
  const panel = root.locator('[data-panel="seasons"]');
  await expect(panel.locator('.gmt-season')).toHaveCount(8);
  await expect(panel).toContainText('عيد التحرير');
  await expect(panel).not.toContainText('يوم الشهيد');
});

test('seasons: the manager edits a date, hides one, adds one — saved on the branch', async ({ page }) => {
  const root = await open(page);
  let saved = null;
  page.on('request', r => { if (r.method() === 'PATCH' && /\/stores/.test(r.url())) saved = JSON.parse(r.postData()).occasions; });
  await root.locator('.gmt-pill[data-tool="seasons"]').click();
  const panel = root.locator('[data-panel="seasons"]');
  await panel.locator('[data-occ="edit"]').click();
  const row = t => panel.locator('.gmt-oe').filter({ has: page.locator(`input[data-oe="t"][value="${t}"]`) });
  await row('عيد الأم').locator('[data-oe="md"]').fill('2026-03-22');
  await row('عيد الحب').locator('[data-oe="off"]').check();
  await panel.locator('[data-occ="add"]').click();
  const nw = panel.locator('.gmt-oe[data-i="new"]');
  await nw.locator('[data-oe="t"]').fill('ذكرى افتتاح المحل');
  await nw.locator('[data-oe="md"]').fill('2026-12-01');
  await panel.locator('[data-occ="save"]').click();
  await expect(panel.locator('.gmt-season').first()).toBeVisible();
  await expect.poll(() => saved).not.toBeNull();
  expect(saved.find(o => o.t === 'عيد الأم').md).toBe('03-22');
  expect(saved.find(o => o.t === 'عيد الحب').off).toBe(true);
  expect(saved.find(o => o.t === 'ذكرى افتتاح المحل')).toMatchObject({ md: '12-01', custom: true });
  await expect(panel.locator('.gmt-seasons')).not.toContainText('عيد الحب');
  await expect(panel.locator('.gmt-seasons')).toContainText('ذكرى افتتاح المحل');
});

test('staff without edit_settings: no «تعديل المناسبات»', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 900 });
  await install(page, { generic: true, db: { ...db(), staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'staff', permissions: {}, full_name: 'م' }] } });
  await page.goto('/index-ar.html');
  const root = page.locator('[data-gm-tools="m"]');
  await root.locator('.gmt-pill[data-tool="seasons"]').click();
  await expect(root.locator('[data-panel="seasons"] .gmt-season').first()).toBeVisible();
  await expect(root.locator('[data-occ="edit"]')).toHaveCount(0);
});
