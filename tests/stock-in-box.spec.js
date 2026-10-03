// Goods-in voucher: new pieces need a box from the shop's boxes; returned pieces can move to a box.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('goods in from an intermediary: box chosen for new and returned pieces', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  let sent = null;
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    stock_parties: [{ id: 'sp1', store_id: STORE, name: 'أبو سمير', kind: 'intermediary' }],
    traders: [], gold_prices: [], piece_classification_options: [], diamond_pieces: [], stock_vouchers: [],
    pieces: [
      { id: 'a', store_id: STORE, barcode: '000001', box_name: 'واجهة 1', status: 'available', karat: 18, weight_grams: 5 },
      { id: 'h', store_id: STORE, barcode: '000002', box_name: 'خواتم', status: 'at_intermediary', karat: 18, weight_grams: 3, party_id: 'sp1' },
    ],
  }, rpc: { stock_in_from_party: a => { sent = a; return { body: 'v1' }; } } });
  page.on('dialog', d => d.message().includes('طباعة') ? d.dismiss() : d.accept());
  await page.goto('/stock-transfer-ar.html');
  await page.waitForFunction(() => document.querySelectorAll('#return-box option').length > 1);
  await page.selectOption('#party-select', 'p:sp1');
  await page.evaluate(() => showTab('in'));
  await page.evaluate(() => addNewRow());
  const row = page.locator('.new-row').first();
  await row.locator('[data-f="weight"]').fill('4');
  await row.locator('[data-f="fab_per_gram"]').fill('10');
  await page.click('#in-btn');
  await expect(page.locator('#save-error')).toContainText('اختر الصندوق');
  await row.locator('[data-f="box_name"]').selectOption('خواتم');
  await page.selectOption('#return-box', 'واجهة 1');
  await page.click('#in-btn');
  await expect.poll(() => sent).not.toBeNull();
  expect(sent.new_lines[0].box_name).toBe('خواتم');
  expect(sent.p_return_box).toBe('واجهة 1');
  expect(errs).toEqual([]);
});
