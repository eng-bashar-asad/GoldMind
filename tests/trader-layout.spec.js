// Trader page on a computer: card | form | photo of the piece being given out + movements.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('trader page: photo of the scanned piece shows beside the give-out form', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }], trader_movements: [], gold_prices: [],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000034', status: 'available', karat: 18, weight_grams: 15.89, accounting_weight_grams: 15.89,
               cost_fabrication_per_gram: 4, description_ar: 'إسوارة', photo_url: 'icon-192.png' },
             { id: 'p2', store_id: STORE, barcode: '000035', status: 'available', karat: 18, weight_grams: 5, accounting_weight_grams: 5, description_ar: 'خاتم' }]
  } });
  await page.setViewportSize({ width: 1600, height: 900 });
  await page.goto('/ledger-ar.html?trader=t1&action=give');
  await page.waitForFunction(() => typeof setGiveStockMode === 'function' && currentTraderId === 't1');
  await expect(page.locator('#give-stock-form')).not.toHaveClass(/hidden/);   // ?action=give opens it
  await page.evaluate(() => setGiveStockMode('barcode'));
  const panel = page.locator('#gs-photo-panel');
  await page.fill('#gs-barcode-input', '000034');
  await page.press('#gs-barcode-input', 'Enter');
  await expect(panel.locator('img[src="icon-192.png"]')).toBeVisible();
  await page.fill('#gs-barcode-input', '000035');
  await page.press('#gs-barcode-input', 'Enter');
  await expect(panel).toContainText('لا توجد صورة');               // last scanned has no photo
  await panel.locator('button[title="000034"]').click();
  await expect(panel).toContainText('15.89');
  // three columns side by side on a computer
  const x = async sel => (await page.locator(sel).boundingBox()).x;
  expect(await x('#gm-side-col')).toBeLessThan(await x('#gm-forms-col'));
  await page.screenshot({ path: '/tmp/claude-0/-home-claude/4e4a4d3c-50ba-5175-802c-0c549ceb7120/scratchpad/trader.png' });
  await page.evaluate(() => toggleGiveStockForm());
  await expect(panel).toHaveClass(/hidden/);
  expect(errs).toEqual([]);
});
