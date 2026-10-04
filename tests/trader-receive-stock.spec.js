// Goods in from a trader: a barcoded piece (box required) and a bulk weight line, sent as one RPC.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('receive from trader: piece + bulk go to stock and account together', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  let sent = null;
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'AED', vat_rate: 5 }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'تاجر أ' }],
    trader_movements: [],
    pieces: [{ id: 'a', store_id: STORE, barcode: '000001', box_name: 'واجهة 1', status: 'available', karat: 18 }],
  }, rpc: { trader_receive_stock: a => { sent = a; return { body: { barcodes: ['000002'] } }; } } });
  page.on('dialog', d => d.accept().catch(() => {}));
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/ledger-ar.html?trader=t1&action=receive');
  await page.waitForFunction(() => !document.getElementById('receive-stock-form').classList.contains('hidden') && typeof rsBoxes !== 'undefined' && rsBoxes && rsBoxes.length === 2);
  const line = n => page.locator('#rs-lines-list > div').nth(n);
  await line(0).locator('input[type=number]').nth(0).fill('4.5');
  await line(0).locator('input[type=number]').nth(2).fill('10');
  await line(0).locator('select').nth(1).selectOption('');
  await page.click('#rs-btn');
  await expect(page.locator('#rs-error')).toContainText('اختر الصندوق');
  await line(0).locator('select').nth(1).selectOption('واجهة 1');
  await page.click('button:has-text("أضف سطر آخر")');
  await line(1).locator('select').nth(0).selectOption('bulk');
  await line(1).locator('input[type=number]').nth(0).fill('100');
  await page.click('#rs-btn');
  await expect.poll(() => sent).not.toBeNull();
  expect(sent.p_trader).toBe('t1');
  expect(sent.p_lines.map(l => [l.kind, l.weight, l.box_name])).toEqual([['piece', 4.5, 'واجهة 1'], ['bulk', 100, 'واجهة 1']]);
  expect(sent.p_vat_rate).toBe(5);
  expect(errs).toEqual([]);
});
