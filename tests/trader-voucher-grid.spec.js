// Computer, one voucher: pieces show as a grid of cards (several per row) with the return action on hover; print keeps the rows.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-11-19T10:00:00Z';
const mv = (id, pid, bc, w) => ({ id, store_id: STORE, trader_id: 't1', movement_type: 'debt_decrease', source: 'stock_given', batch_id: 'b1', piece_id: pid, karat: 18, weight_grams: w, gold_24k_equivalent: w * 0.75, fab_fee_per_gram: 19, fab_fee_amount: w * 19, notes: `إخراج بضاعة — باركود ${bc} (أسوارة)`, created_at: T });
test('voucher pieces as a grid on the computer', async ({ page }) => {
  await page.setViewportSize({ width: 1400, height: 900 });
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { generic: true, realCdn: !!process.env.SHOT, db: {
    stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'هادي عطار' }],
    pieces: ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'].map((id, i) => ({ id, store_id: STORE, barcode: '00099' + i })),
    trader_movements: [mv('m1', 'p1', '000990', 13.06), mv('m2', 'p2', '000991', 6), mv('m3', 'p3', '000992', 2.08), mv('m4', 'p4', '000993', 9.4), mv('m5', 'p5', '000994', 12.47), mv('m6', 'p6', '000995', 2.23)],
  } });
  await page.goto('/trader-statement-print-ar.html?trader=t1&batch=b1');
  const cards = page.locator('.stg .stg-c');
  await expect(cards).toHaveCount(6);
  await expect(page.locator('tr.st-p').first()).toBeHidden();
  const boxes = await Promise.all([0, 1, 2].map(i => cards.nth(i).boundingBox()));
  expect(Math.abs(boxes[0].y - boxes[2].y)).toBeLessThan(2); // at least three on one row
  await expect(cards.last()).toContainText('13.06'); // newest piece first, like the rows
  const act = cards.first().locator('.stg-act');
  await expect(act).toHaveCSS('opacity', '0');
  await cards.first().hover();
  await expect(act).toHaveCSS('opacity', '1');
  await expect(act.locator('button')).toContainText('إرجاع للمخزن');
  if (process.env.SHOT) await page.screenshot({ path: '/tmp/grid.png' });
  await page.emulateMedia({ media: 'print' });
  await expect(page.locator('tr.st-p').first()).toBeVisible();
  await expect(page.locator('tr.st-grid-row').first()).toBeHidden();
  expect(errs).toEqual([]);
});
