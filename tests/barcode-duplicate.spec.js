// A barcode that differs from an existing one only by spaces or letter case is the same sticker: refused.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

async function setup(page) {
  return install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'b' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: 'M B 459  W', status: 'available', karat: 18, weight_grams: 18.34, box_name: 'Mirruba' }],
    piece_classification_options: [], zebra_label_fields: [],
  } });
}

async function addWith(page, code) {
  await page.goto('/inventory-add.html');
  await page.waitForFunction(() => typeof zebraPrintStore !== 'undefined' && zebraPrintStore);
  await page.locator('#barcode-id').fill(code);
  await page.locator('#weight').fill('18.33');
  await page.evaluate(() => {
    const k = document.getElementById('karat'); if (![...k.options].some(o => o.value === '18')) k.add(new Option('18', '18')); k.value = '18';
    const b = document.getElementById('box-name'); b.add(new Option('Mirruba', 'Mirruba')); b.value = 'Mirruba';
  });
  await page.locator('#save-btn').click();
}

test('same barcode with different spaces is refused', async ({ page }) => {
  const calls = await setup(page);
  await addWith(page, 'mb459w');
  await expect(page.locator('#save-message')).toContainText('هذا الباركود مستخدم لقطعة أخرى: M B 459  W');
  expect(calls.some(c => c.method === 'POST' && c.name === 'pieces')).toBe(false);
});

test('a new barcode is saved with its spaces tidied', async ({ page }) => {
  const calls = await setup(page);
  await addWith(page, '  M B  460   W ');
  await expect.poll(() => calls.find(c => c.method === 'POST' && c.name === 'pieces')).toBeTruthy();
  expect(JSON.parse(calls.find(c => c.method === 'POST' && c.name === 'pieces').body).barcode).toBe('M B 460 W');
});
