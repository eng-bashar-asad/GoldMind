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

// New pieces made from a piece held by the intermediary: that original is sent as the source
// (closed as «حُوّلت لقطع جديدة»). One held piece is picked by itself; with two, the user must choose.
test('goods in: new pieces name the original they were made from', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  let sent = null;
  const line = (id, pid, bc) => ({ id, voucher_id: 'o1', party_id: 'sp1', direction: 'out', piece_id: pid, barcode: bc, karat: 18, weight_grams: 10, accounting_weight_grams: 10, cost_value: 0 });
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    stock_parties: [{ id: 'sp1', store_id: STORE, name: 'تعديل داخلي', kind: 'intermediary' }],
    traders: [], gold_prices: [], piece_classification_options: [], diamond_pieces: [],
    stock_vouchers: [{ id: 'o1', store_id: STORE, party_id: 'sp1', direction: 'out', voucher_number: 'OUT-00001', created_at: '2026-10-27T10:00:00Z' }],
    stock_voucher_lines: [line('l1', 'c1', '000010'), line('l2', 'c2', '000011')],
    pieces: [
      { id: 'a', store_id: STORE, barcode: '000001', box_name: 'عيار 18', status: 'available', karat: 18, weight_grams: 5 },
      { id: 'c1', store_id: STORE, barcode: '000010', box_name: 'عيار 18', status: 'at_intermediary', karat: 18, weight_grams: 10 },
      { id: 'c2', store_id: STORE, barcode: '000011', box_name: 'عيار 18', status: 'at_intermediary', karat: 18, weight_grams: 10 },
    ],
  }, rpc: { stock_in_from_party: a => { sent = a; return { body: 'v1' }; } } });
  page.on('dialog', d => d.message().includes('طباعة') ? d.dismiss() : d.accept());
  await page.goto('/stock-transfer-ar.html');
  await page.waitForFunction(() => document.querySelectorAll('#return-box option').length > 1);
  await page.selectOption('#party-select', 'p:sp1');
  await expect(page.locator('.held-row')).toHaveCount(2);
  await page.evaluate(() => showTab('in'));
  await page.evaluate(() => addNewRow());
  const row = page.locator('.new-row').first();
  await row.locator('[data-f="weight"]').fill('6');
  await row.locator('[data-f="fab_per_gram"]').fill('0');
  await row.locator('[data-f="box_name"]').selectOption('عيار 18');
  await page.click('#in-btn');
  await expect(page.locator('#save-error')).toContainText('حدّد القطعة الأصلية');
  // ticking «back as is» on one leaves a single candidate: it becomes the source by itself
  await page.locator('.held-row[data-id="c2"] .held-cb').check();
  await page.click('#in-btn');
  await expect.poll(() => sent).not.toBeNull();
  expect(sent.p_source_piece_ids).toEqual(['c1']);
  expect(sent.return_piece_ids).toEqual(['c2']);
  // the two choices on one piece exclude each other
  await page.locator('.held-row[data-id="c1"] .held-src').check();
  await page.locator('.held-row[data-id="c1"] .held-cb').check();
  await expect(page.locator('.held-row[data-id="c1"] .held-src')).not.toBeChecked();
  expect(errs).toEqual([]);
});

// Part of the result can go to a scrap box: only karat + weight are sent, flagged to_scrap.
test('goods in: a row can go to the scrap box', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  let sent = null;
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    stock_parties: [{ id: 'sp1', store_id: STORE, name: 'تعديل داخلي', kind: 'intermediary' }],
    traders: [], gold_prices: [], piece_classification_options: [], diamond_pieces: [], stock_vouchers: [],
    pieces: [{ id: 'a', store_id: STORE, barcode: '000001', box_name: 'عيار 18', status: 'available', karat: 18, weight_grams: 5 }],
  }, rpc: { stock_in_from_party: a => { sent = a; return { body: 'v1' }; } } });
  page.on('dialog', d => d.message().includes('طباعة') ? d.dismiss() : d.accept());
  await page.goto('/stock-transfer-ar.html');
  await page.waitForFunction(() => document.querySelectorAll('#return-box option').length > 1);
  await page.selectOption('#party-select', 'p:sp1');
  await page.evaluate(() => showTab('in'));
  await page.evaluate(() => addNewRow());
  const row = page.locator('.new-row').first();
  await row.locator('[data-f="box_name"]').selectOption('__scrap:21');
  await expect(row.locator('[data-f="fab_per_gram"]').locator('xpath=..')).toHaveClass(/\bhidden\b/);
  await expect(row.locator('[data-f="karat"]')).toHaveValue('21');
  await row.locator('[data-f="weight"]').fill('1.25');
  await page.click('#in-btn');
  await expect.poll(() => sent).not.toBeNull();
  expect(sent.new_lines).toEqual([{ to_scrap: true, karat: 21, weight: 1.25 }]);
  expect(errs).toEqual([]);
});
