// إنتاج القطع: karat scrap boxes; production goes through the add-piece page
// and each saved piece takes its weight from the box (oldest purchase first).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const lot = (id, box, k, w, at) => ({ id, store_id: STORE, box_name: box, karat: k, weight_grams_total: w, weight_grams_remaining: w, cost_fabrication_per_gram: 0, created_at: at || '2026-10-01T00:00:00Z' });
const base = (lots) => ({
  stores: [{ id: STORE, currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  gold_stock_lots: lots, piece_classification_options: [], pieces: [{ id: 'px', store_id: STORE, barcode: '000001', box_name: 'قطع ذهبية', status: 'available', weight_grams: 1, karat: 18 }], zebra_label_fields: []
});

test('production page: karat scrap boxes link to the add-piece page', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { generic: true, db: base([lot('l1', 'كسر 18', 18, 18.25), lot('l2', 'كسر 18', 18, 31.96), lot('l3', 'ذهب مشغول', 21, 10)]) });
  await page.goto('/stock-production-ar.html');
  const list = page.locator('#lots-list');
  await expect(list).toContainText('50.21 غ');
  await expect(list).toContainText('كسر 24');
  await expect(list).not.toContainText('متبقي');
  const href = await list.locator('a', { hasText: 'كسر 18' }).getAttribute('href');
  expect(new URL(href, 'http://x/').searchParams.get('prod')).toBe('كسر 18');
  await page.getByText('ذهب مشغول').click();
  await expect(list.locator('a[href="inventory-add.html?lot=l3"]')).toBeVisible();
  expect(errs).toEqual([]);
});

test('add-piece in production mode takes the weight from the scrap box on the server', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const calls = await install(page, { generic: true, rpc: {
      next_piece_barcode: () => ({ body: '000900' }),
      production_take: () => ({ body: { ok: true } }) },
    db: base([lot('l1', 'كسر 18', 18, 18.25, '2026-10-01T00:00:00Z'), lot('l2', 'كسر 18', 18, 31.96, '2026-10-02T00:00:00Z')]) });
  await page.goto('/inventory-add.html?prod=' + encodeURIComponent('كسر 18'));
  await expect(page.locator('#gm-prod-banner')).toContainText('50.21 غ');
  await expect(page.locator('#karat')).toBeDisabled();
  await page.fill('#weight', '60');
  await page.click('#save-btn');
  await expect(page.locator('#save-message')).toContainText('أكبر من المتوفر');
  await page.fill('#weight', '20');
  await page.click('#save-btn');
  await expect.poll(() => calls.filter(c => c.name === 'production_take').length).toBe(1);
  expect(JSON.parse(calls.find(c => c.name === 'production_take').body)).toMatchObject({ p_box: 'كسر 18' });
  await expect(page.locator('#gm-prod-banner')).toContainText('30.21 غ');
  expect(errs).toEqual([]);
});

// بشار 2026-11-15: «مصدر القطعة» on the add-piece screen — from a trader (posted to his account on save,
// a new trader can be added on the spot) or from the scrap box; the rest of the form is unchanged.
test('add-piece: source «من تاجر» posts each saved piece to the trader, new trader on the spot', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  const db = base([]);
  db.traders = [{ id: 't1', store_id: db.stores[0].id, name: 'مهند' }];
  db.stores[0].vat_rate = 5;
  const calls = await install(page, { generic: true, db, rpc: {
      next_piece_barcode: () => ({ body: '000901' }),
      trader_receive_piece: () => ({ body: { ok: true } }) } });
  page.on('dialog', d => d.accept(d.message().includes('اسم') ? 'سامر' : ''));
  await page.route(/rest\/v1\/traders/, r => r.request().method() === 'POST' ? r.fulfill({ json: { id: 't2', name: 'سامر' } }) : r.fallback());
  await page.goto('/inventory-add.html');
  await expect(page.locator('#piece-source option[value="t:t1"]')).toHaveText('مهند');
  await page.selectOption('#piece-source', '__new_trader__');               // + إضافة تاجر جديد
  await expect(page.locator('#piece-source option', { hasText: 'سامر' })).toHaveCount(1);
  await page.selectOption('#piece-source', 't:t1');
  await expect(page.locator('#source-note')).toContainText('مهند');
  await expect(page.locator('#source-note')).toContainText('5%');
  await page.fill('#weight', '10');
  await page.click('#save-btn');
  await expect.poll(() => calls.filter(c => c.name === 'trader_receive_piece').length).toBe(1);
  const body = JSON.parse(calls.find(c => c.name === 'trader_receive_piece').body);
  expect(body).toMatchObject({ p_trader: 't1', p_vat_rate: 5 });
  expect(body.p_batch).toBeTruthy();
  await expect(page.locator('#save-message')).toContainText('حساب مهند');
  expect(errs).toEqual([]);
});

test('add-piece: source «كسر عيار 18» takes the weight from that scrap box', async ({ page }) => {
  const calls = await install(page, { generic: true, rpc: {
      next_piece_barcode: () => ({ body: '000902' }),
      production_take: () => ({ body: { ok: true } }) },
    db: base([lot('l1', 'كسر 18', 18, 18.25, '2026-10-01T00:00:00Z')]) });
  await page.goto('/inventory-add.html');
  await page.selectOption('#piece-source', 's:18');
  await expect(page.locator('#gm-prod-banner')).toContainText('18.25 غ');
  await expect(page.locator('#karat')).toBeDisabled();
  await page.fill('#weight', '5');
  await page.click('#save-btn');
  await expect.poll(() => calls.filter(c => c.name === 'production_take').length).toBe(1);
  expect(JSON.parse(calls.find(c => c.name === 'production_take').body)).toMatchObject({ p_box: 'كسر 18' });
  await page.selectOption('#piece-source', '');                               // back to normal entry
  await expect(page.locator('#karat')).toBeEnabled();
  await expect(page.locator('#gm-prod-banner')).toHaveClass(/\bhidden\b/);
});
