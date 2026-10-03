// Scrap box: purchases from individuals have no single-piece (barcode) option;
// scrap profit (weight × shop price at purchase − paid) shows in the profit report;
// scrap leaves the box to a trader at cost.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const base = extra => ({
  stores: [{ id: STORE, name: 'محل', currency: 'AED', vat_rate: 0 }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  ...extra
});

test('buying from an individual offers scrap only (no barcode piece)', async ({ page }) => {
  await install(page, { generic: true, db: base({ traders: [], gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 360 }] }) });
  await page.goto('/create-invoice-v2-ar.html');
  await expect(page.locator('#itemModePiece')).not.toHaveClass(/hidden/);
  await page.click('#tabRetail');
  await expect(page.locator('#itemModePiece')).toHaveClass(/hidden/);
  await expect(page.locator('#itemModeBulk')).toHaveText('ذهب كسر');
  await page.fill('#manual-weight', '200');
  await page.fill('#manual-price', '70000');
  await expect(page.locator('#scrap-ref')).toContainText('ربح شراء الكسر');
  await expect(page.locator('#scrap-ref')).toContainText('2,000');
});

test('profit report: scrap bought below the shop price is profit, not cash', async ({ page }) => {
  const T = '2026-09-15T10:00:00Z';
  await install(page, { db: base({
    gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 360 }], pieces: [], diamond_pieces: [],
    invoices: [{ id: 'b1', store_id: STORE, invoice_number: 'PINV-1', type: 'buyRetail', status: 'paid', created_by: STAFF, created_at: T, total_amount: 70000 }],
    invoice_items: [{ invoice_id: 'b1', karat: 18, weight_grams: 200, accounting_weight_grams: 200, line_total: 70000, gold_price_per_gram: 360, gold_stock_lot_id: 'l1' }],
    trader_movements: [], expense_entries: [] }) });
  await page.goto('/profit-report-ar.html');
  await page.fill('#date-from', '2026-09-01');
  await page.fill('#date-to', '2026-09-30');
  await page.click('#apply-filters-btn');
  const br = page.locator('#pr-brief');
  await expect(br.locator('tr', { hasText: 'ربح شراء الكسر' })).toContainText('2,000.00');
  await expect(br.locator('tr', { hasText: 'صافي ربح المحل' })).toContainText('2,000.00');
  await expect(br.locator('tr', { hasText: 'مشتريات الكسر' }).last()).toContainText('70,000.00');
});

test('trader account: give scrap from the box at cost', async ({ page }) => {
  const calls = await install(page, { db: base({
    traders: [{ id: 't1', store_id: STORE, name: 'وسيط تعديل' }], trader_movements: [], cash_movements: [],
    gold_stock_lots: [
      { id: 'l1', store_id: STORE, karat: 18, box_name: 'كسر 18', weight_grams_remaining: 200, items: [{ weight_grams: 200, line_total: 70000, invoice: { type: 'buyRetail' } }] },
      { id: 'l2', store_id: STORE, karat: 18, box_name: 'كسر 18', weight_grams_remaining: 50, items: [{ weight_grams: 50, line_total: 18000, invoice: { type: 'buyRetail' } }, { weight_grams: 10, line_total: 99999, invoice: { type: 'sale' } }] } ] }),
    rpc: { give_scrap_to_trader: () => ({ body: { id: 'm', cost: 88000 } }) } });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/ledger-ar.html?trader=t1&action=give');
  await page.waitForFunction(() => typeof currentTraderId !== 'undefined' && currentTraderId === 't1');
  await page.evaluate(() => { if (document.getElementById('give-stock-form').classList.contains('hidden')) toggleGiveStockForm(); });
  await page.click('#gs-mode-scrap-btn');
  await expect(page.locator('#gsc-boxes')).toContainText('250.00 غ');
  await expect(page.locator('#gsc-boxes')).toContainText('88,000');           // sale line ignored in cost
  await expect(page.locator('#gsc-weight')).toHaveValue('250');
  await expect(page.locator('#gsc-preview')).toContainText('187.50 غ');       // 250 × 18/24
  page.on('dialog', d => d.accept());
  await page.click('#gsc-btn');
  await expect.poll(() => calls.some(c => c.name === 'give_scrap_to_trader')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'give_scrap_to_trader').body)).toMatchObject({ p_trader: 't1', p_karat: 18, p_weight: 250 });
});
