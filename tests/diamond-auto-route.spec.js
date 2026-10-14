// Pieces with diamonds are saved in the stock like any piece (Bashar 2026-10-14: no separate diamond warehouse for them).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

async function setup(page, diamondsEnabled) {
  return install(page, {
    generic: true,
    db: {
      stores: [{ id: STORE, name: 'x', currency: 'AED', diamonds_enabled: diamondsEnabled }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'b' }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      pieces: [], diamond_pieces: [], piece_classification_options: [], zebra_label_fields: [],
    },
    rpc: { next_piece_barcode: a => ({ body: a.category === 'diamond' ? 'D-0001' : 'G-0001' }) },
  });
}

async function fillAndSave(page, { diCarat, diPrice }) {
  await page.goto('/inventory-add.html');
  await page.waitForFunction(() => typeof zebraPrintStore !== 'undefined' && zebraPrintStore);
  await page.locator('#weight').fill('10');
  await page.locator('#accounting-weight').fill('9.5');
  await page.evaluate(() => {
    const k = document.getElementById('karat'); if (![...k.options].some(o => o.value === '18')) k.add(new Option('18', '18')); k.value = '18';
    const b = document.getElementById('box-name'); b.add(new Option('ألماس', 'ألماس')); b.value = 'ألماس';
  });
  await page.locator('#fab-cost').fill('30');
  if (diCarat) await page.locator('#accent-diamond-carat').fill(diCarat);
  if (diPrice) await page.locator('#accent-diamond-price').fill(diPrice);
  await page.locator('#center-stone-carat').fill('0.5');
  await page.locator('#center-stone-price').fill('1000');
  await page.locator('#save-btn').click();
}

test('Di weight + carat price → stays in the stock as a piece with its diamond', async ({ page }) => {
  const calls = await setup(page, true);
  await fillAndSave(page, { diCarat: '0.39', diPrice: '500' });
  await expect.poll(() => calls.find(c => c.method === 'POST' && c.name === 'pieces')).toBeTruthy();
  const row = JSON.parse(calls.find(c => c.method === 'POST' && c.name === 'pieces').body);
  expect(row).toMatchObject({ barcode: 'G-0001', weight_grams: 10, accounting_weight_grams: 9.5, karat: 18,
    accent_diamond_carat: 0.39, accent_diamond_price_per_carat: 500, box_name: 'ألماس' });
  expect(calls.some(c => c.method === 'POST' && c.name === 'diamond_pieces')).toBe(false);
});

for (const [name, enabled, carat, price] of [['diamonds off', false, '0.39', '500'], ['no carat price', true, '0.39', '']]) {
  test(`${name} → stays a gold piece`, async ({ page }) => {
    const calls = await setup(page, enabled);
    await fillAndSave(page, { diCarat: carat, diPrice: price });
    await expect.poll(() => calls.find(c => c.method === 'POST' && c.name === 'pieces')).toBeTruthy();
    expect(JSON.parse(calls.find(c => c.method === 'POST' && c.name === 'pieces').body).barcode).toBe('G-0001');
    expect(calls.some(c => c.method === 'POST' && c.name === 'diamond_pieces')).toBe(false);
  });
}
