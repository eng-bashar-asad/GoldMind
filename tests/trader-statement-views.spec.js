// Trader statement: one chronological ledger (a line per voucher), "سندات" vs "تفاصيل",
// photos on/off, the type filter, and running balances (+ trader owes shop, − shop owes trader).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = '2026-09-30T10:00:00Z';
const mv = (id, pid, bc, w24, fab) => ({ id, store_id: STORE, trader_id: 't1', movement_type: 'debt_decrease', source: 'stock_given', batch_id: 'b1', piece_id: pid, karat: 18, weight_grams: w24 * 4 / 3, gold_24k_equivalent: w24, fab_fee_amount: fab, notes: `إخراج بضاعة — باركود ${bc} (خاتم)`, created_at: T });
const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  traders: [{ id: 't1', store_id: STORE, name: 'تاجر أ', phone: '0999' }],
  pieces: [{ id: 'p1', store_id: STORE, barcode: '000436', photo_url: 'https://example.com/a.jpg' }, { id: 'p2', store_id: STORE, barcode: '000415' }],
  trader_movements: [mv('m1', 'p1', '000436', 7.5, 150), mv('m2', 'p2', '000415', 15, 300),
    { id: 'm3', store_id: STORE, trader_id: 't1', movement_type: 'debt_increase', source: 'cash_in', gold_24k_equivalent: 0, fab_fee_amount: 100, created_at: T }],
});

test('one ledger: a line per voucher, running balances, vouchers vs details, photos toggle', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await page.addInitScript(() => { try { localStorage.clear(); } catch (e) {} });
  await install(page, { db: db() });
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  const rows = page.locator('#stLedgerRows');
  // two lines: the voucher b1 (gold given) and the cash payment m3
  await expect(rows.locator('tr.st-m')).toHaveCount(2);
  await expect(rows.locator('tr.st-p')).toHaveCount(0);
  await expect(rows).toContainText('إعطاء بضاعة · 2 قطعة · عيار 18');
  await expect(rows).toContainText('22.50');     // gold 24k, trader owes the shop
  // newest on top (بشار 2026-11-15): same time here, so the later-entered cash line comes first
  await expect(rows.locator('tr.st-m').nth(1).locator('td').nth(3)).toHaveText('30.00'); // standing weight 18k: 10 + 20
  await expect(rows.locator('tr.st-m').nth(0).locator('td').nth(3)).toHaveText('—');       // cash: no weight
  await expect(rows).toContainText('450.00');    // making
  await expect(rows).toContainText('-100.00');   // cash the shop paid out: shop owes trader
  await expect(page.locator('#stLedgerFoot')).toContainText('22.50');
  await expect(page.locator('#stLedgerFoot')).toContainText('350.00'); // final cash: 450 - 100
  await expect(page.locator('#stCashRows, #stGoldRows')).toHaveCount(0);

  await page.click('#stOpts [data-view=details]');
  await expect(rows.locator('tr.st-p')).toHaveCount(2);
  await expect(rows.locator('tr.st-p').last().locator('td').nth(3)).toHaveText('10.00');   // first piece of the voucher at the bottom
  await expect(rows).toContainText('000436 (خاتم)');
  await expect(rows).not.toContainText('إخراج بضاعة');
  await expect(rows.locator('img.st-ph')).toHaveCount(1);
  await page.click('#stOpts [data-photos="0"]');
  await expect(rows.locator('img.st-ph')).toHaveCount(0);
  expect(errs).toEqual([]);
});

test('type filter hides lines but balances still count every line', async ({ page }) => {
  await page.addInitScript(() => { try { localStorage.clear(); } catch (e) {} });
  await install(page, { db: db() });
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  await page.click('#stKinds [data-kind=cash]');
  const rows = page.locator('#stLedgerRows');
  await expect(rows.locator('tr.st-m')).toHaveCount(1);
  await expect(rows).toContainText('قبض كاش من التاجر');
  await expect(page.locator('#stLedgerFoot')).toContainText('350.00');
  await page.click('#stKinds [data-kind=all]');
  await expect(rows.locator('tr.st-m')).toHaveCount(2);
});

test('return one piece to stock from the statement', async ({ page }) => {
  const calls = await install(page, { db: db(), rpc: { trader_return_piece: () => ({ body: { ok: true } }) } });
  page.on('dialog', d => d.accept());
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  await page.click('#stOpts [data-view=details]');
  const btn = page.locator('#stLedgerRows tr.st-p button.st-ret').last();
  await expect(btn).toBeVisible();
  await btn.click();
  await expect.poll(() => calls.some(c => c.name === 'trader_return_piece')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'trader_return_piece').body)).toEqual({ p_movement: 'm1' });
});

test('no money at all in the period: the cash card is hidden', async ({ page }) => {
  const d = db();
  d.trader_movements = [];
  await install(page, { db: d });
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  await expect(page.locator('#stCashCards')).toHaveClass(/\bhidden\b/);
  await expect(page.locator('#stLedgerRows')).toContainText('لا توجد حركات بهذه الفترة');
});

test('statement shows the making cost per gram before the total making cost', async ({ page }) => {
  await page.addInitScript(() => { try { localStorage.clear(); } catch (e) {} });
  const d = db();
  d.trader_movements[0].fab_fee_per_gram = 15; d.trader_movements[1].fab_fee_per_gram = 15;
  await install(page, { db: d });
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  const heads = await page.locator('.stmt-table thead th').allTextContents();
  expect(heads.indexOf('مصنعية/غ')).toBe(heads.findIndex(h => h.startsWith('نقد')) - 1);
  await expect(page.locator('#stLedgerRows tr.st-m', { hasText: 'إعطاء بضاعة' }).locator('td').nth(5)).toHaveText('15.00');
  await page.click('#stOpts [data-view=details]');
  await expect(page.locator('#stLedgerRows tr.st-p').first().locator('td').nth(5)).toHaveText('15.00');
});

// Phone: «أ — بطاقات» — one card per voucher with total tiles, pieces under it in «تفاصيل»; the table is for computer/print.
test('phone: statement as cards, with the standing-weight tile and return button', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => { try { localStorage.clear(); localStorage.setItem('gm_stmt_view', 'details'); } catch (e) {} });
  const calls = await install(page, { db: db(), rpc: { trader_return_piece: () => ({ body: { ok: true } }) } });
  page.on('dialog', d => d.accept());
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  const cards = page.locator('#stCards section.stc');
  await expect(cards).toHaveCount(2);
  const give = cards.filter({ hasText: 'إعطاء بضاعة' });
  await expect(give).toContainText('الوزن القائم ع18');
  await expect(give.locator('.stc-tile').first()).toContainText('30.00 g');
  await expect(give.locator('.stc-p')).toHaveCount(2);
  await expect(page.locator('#stCards .stc-end')).toContainText('350.00');
  await give.locator('button.stc-ret').first().click();
  await expect.poll(() => calls.some(c => c.name === 'trader_return_piece')).toBe(true);
});

// بشار 2026-11-15: a voucher with two karats shows each karat's weight on its own smaller line — never cut with «...»
test('phone: mixed-karat voucher weight tile shows every karat in full', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => { try { localStorage.clear(); localStorage.setItem('gm_stmt_view', 'details'); } catch (e) {} });
  const d = db();
  d.trader_movements[1].karat = 24; d.trader_movements[1].weight_grams = 1250.5; // big number on a second karat
  await install(page, { db: d });
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  const tile = page.locator('#stCards section.stc', { hasText: 'إعطاء بضاعة' }).locator('.stc-tile b').first();
  await expect(tile).toContainText('ع18');
  await expect(tile).toContainText('1,250.50 g');
  await expect(tile).toHaveClass(/stc-multi/);
  expect(await tile.evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true); // nothing hidden
});

// بشار 2026-11-15: tapping a piece photo in the statement opens it large
test('phone: tapping a piece photo opens it large', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => { try { localStorage.clear(); localStorage.setItem('gm_stmt_view', 'details'); } catch (e) {} });
  const d = db();
  d.trader_movements.forEach(m => { if (m.piece_id) m.photo_url = 'https://example.com/p.svg'; });
  (d.inventory_pieces || []).forEach(p => { p.photo_url = 'https://example.com/p.svg'; });
  await page.route(/example\.com/, r => r.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"/>' }));
  await install(page, { db: d });
  await page.goto('/trader-statement-print-ar.html?trader=t1');
  await page.locator('img.stc-ph').first().click();
  await expect(page.locator('#gm-photo-viewer')).toBeVisible();
});
