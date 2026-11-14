// «إخراج» to a party can take weight from the scrap boxes, not only barcoded pieces (بشار 2026-11-14).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('stock out: scrap from «كسر 21» goes in the voucher, limited to what the box holds', async ({ page }) => {
  let sent = null;
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    stock_parties: [{ id: 'w1', store_id: STORE, name: 'ورشة', kind: 'intermediary' }],
    gold_stock_lots: [
      { id: 'l1', store_id: STORE, karat: 21, box_name: 'كسر 21', weight_grams_total: 300, weight_grams_remaining: 300, created_at: '2026-11-01T10:00:00Z' },
      { id: 'l2', store_id: STORE, karat: 21, box_name: 'كسر 21', weight_grams_total: 62.13, weight_grams_remaining: 62.13, created_at: '2026-11-02T10:00:00Z' }],
    gold_prices: [{ store_id: STORE, karat: 21, price_per_gram: 100 }],
    stock_vouchers: [], stock_voucher_lines: [], traders: [], pieces: [], diamond_pieces: [], piece_classification_options: [],
  }, rpc: { stock_out_to_party_v2: a => { sent = a; return { body: 'v1' }; } } });
  page.on('dialog', d => d.accept().catch(() => {}));
  await page.goto('/stock-transfer-ar.html');
  await expect(page.locator('#out-scrap-k')).toContainText('كسر 21 — 362.130');
  await page.selectOption('#party-select', 'p:w1');
  await page.fill('#out-scrap-w', '400');
  await page.click('button:has-text("أضف الكسر")');
  await expect(page.locator('#out-msg')).toContainText('فيه 362.130 غ فقط');
  await page.fill('#out-scrap-w', '50.5');
  await page.click('button:has-text("أضف الكسر")');
  await expect(page.locator('#out-list')).toContainText('صندوق كسر 21');
  await page.click('#out-btn');
  await expect.poll(() => sent).not.toBeNull();
  expect(sent).toMatchObject({ target_party_id: 'w1', piece_ids: [], p_scrap: [{ karat: 21, weight: 50.5 }] });
});

test('stock in: each new piece has a «تصوير» button (webcam / phone camera)', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    stock_parties: [{ id: 'w1', store_id: STORE, name: 'ورشة', kind: 'intermediary' }],
    gold_stock_lots: [], gold_prices: [], stock_vouchers: [], stock_voucher_lines: [], traders: [], pieces: [], diamond_pieces: [], piece_classification_options: [],
  } });
  // a webcam that returns one frame
  await page.route('**/gm-camera.js*', r => r.fulfill({ contentType: 'application/javascript',
    body: "var GMCamera = { isSupported: () => true, capture: async () => new File([new Uint8Array([255, 216, 255])], 'cam.jpg', { type: 'image/jpeg' }) };" }));
  await page.goto('/stock-transfer-ar.html');
  await page.selectOption('#party-select', 'p:w1');
  await page.evaluate(() => showTab('in'));
  await page.click('#new-pieces-box button:has-text("قطعة")');
  const row = page.locator('.new-row').last();
  await row.locator('button:has-text("تصوير")').click();
  await expect(row.locator('.ph-prev')).toBeVisible();
  expect(await row.evaluate(r => photoOf(r.querySelector('[data-f="photo"]')).name)).toBe('cam.jpg');
  // or a picture already on the computer
  await expect(row.locator('button:has-text("من الجهاز")')).toBeVisible();
  await row.locator('.ph-file').setInputFiles({ name: 'disk.jpg', mimeType: 'image/jpeg', buffer: Buffer.from([255, 216, 255]) });
  expect(await row.evaluate(r => photoOf(r.querySelector('[data-f="photo"]')).name)).toBe('disk.jpg');
});
