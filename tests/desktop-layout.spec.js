// Computer layout: fixed side menu, small bar on narrow laptops, inventory as a table, sale screen columns.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
});

test('computer: the menu stays open beside the page; phone: it is a drawer', async ({ page }) => {
  await install(page, { db: db() });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/customers-ar.html');
  await expect(page.locator('html')).toHaveClass(/\bgm-desk\b/);
  await expect(page.locator('html')).not.toHaveClass(/\bgm-mini\b/);
  await page.setViewportSize({ width: 1100, height: 800 });
  await expect(page.locator('html')).toHaveClass(/\bgm-mini\b/); // small bar under 1280px
  await page.click('#gmNav .gn-mini');                          // the toggle is remembered
  await page.setViewportSize({ width: 1440, height: 900 });
  await expect(page.locator('html')).not.toHaveClass(/\bgm-mini\b/);
});

test('inventory pieces: a table on the computer, cards on the phone', async ({ page }) => {
  await install(page, { db: db() });
  const piece = { id: 'p1', barcode: '000120', karat: 21, weight_grams: 5, accounting_weight_grams: 4.8, status: 'available', box_name: 'قطع ذهبية', piece_type: 'خاتم' };
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/inventory-list-ar.html');
  const wide = await page.evaluate(p => piecesHtml([p]), piece);
  expect(wide).toContain('<table');
  expect(wide).toContain('000120');
  await page.setViewportSize({ width: 390, height: 844 });
  const narrow = await page.evaluate(p => piecesHtml([p]), piece);
  expect(narrow).toContain('gm-piece');
  expect(await page.evaluate(() => piecesHtml([]))).toBe('');
});

test('sale screen: items table under the entry boxes on the computer, back in place on the phone', async ({ page }) => {
  await install(page, { db: db() });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/new-sale-ar.html');
  await expect(page.locator('#ns-main > #ns-cart')).toHaveCount(1);
  await expect(page.locator('#ns-side > #ns-customer')).toHaveCount(1);
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.locator('#ns-main > #ns-customer')).toHaveCount(1);
  await expect(page.locator('#ns-side > #ns-cart')).toHaveCount(1);
});

test('piece page on the computer: compact specs, suggested price, transfer link, log as a table', async ({ page }) => {
  const d = db();
  d.gold_prices = [{ store_id: STORE, karat: 21, price_per_gram: 300 }];
  d.pieces = [{ id: 'p1', store_id: STORE, barcode: '000120', karat: 21, weight_grams: 5.4, accounting_weight_grams: 5, cost_fabrication_per_gram: 10, color: 'Gold', status: 'available', piece_type: 'خاتم', box_name: 'قطع ذهبية' }];
  d.piece_movements = [{ id: 'm1', store_id: STORE, piece_id: 'p1', event_type: 'created', note: 'إدخال', created_at: '2026-10-10T10:00:00Z' }];
  d.piece_classification_options = []; d.zebra_label_fields = [];
  await install(page, { db: d });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/piece-edit-ar.html?id=p1');
  await expect(page.locator('#pcAcc')).toHaveText('5.00 غ');
  await expect(page.locator('#pcBranch')).toHaveText('محل');
  await expect(page.locator('#pcSuggest')).toHaveText('1,550.00');          // 5 × 300 + 5 × 10
  await expect(page.locator('#pcStones')).toHaveClass(/\bhidden\b/);        // no stones → no card
  await expect(page.locator('#pcMoveBtn')).toHaveAttribute('href', 'branch-transfers-ar.html?barcode=000120');
  await expect(page.locator('#piece-log-list table.pc-log tbody tr')).toHaveCount(1);
});
