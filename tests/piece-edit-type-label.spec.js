// Changing a piece's type on the edit page renews the description the label prints (Arabic + English),
// and the change is written to the piece log.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('a new type renews the label description and is logged', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const calls = await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    piece_classification_options: [
      { id: 'o1', store_id: STORE, field_key: 'type', value: 'عقد', value_en: 'Necklace' },
      { id: 'o2', store_id: STORE, field_key: 'type', value: 'حلق', value_en: 'Earring' },
    ],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '001002', status: 'available', weight_grams: 12.75, karat: 18, piece_type: 'عقد', description_ar: 'عقد', description_en: 'Necklace' }],
    piece_movements: [],
  } });
  await page.goto('/piece-edit-ar.html?id=p1');
  await page.waitForFunction(() => document.querySelectorAll('#piece-type option').length > 2);
  // the edit fields sit in a folded panel: set the value and save as the page would
  await page.evaluate(() => { const s = document.getElementById('piece-type'); s.value = 'حلق'; s.dispatchEvent(new Event('change')); document.getElementById('save-btn').click(); });
  await expect.poll(() => calls.some(c => c.method === 'PATCH' && /\/pieces/.test(c.url))).toBe(true);
  const body = JSON.parse(calls.find(c => c.method === 'PATCH' && /\/pieces/.test(c.url)).body);
  expect(body).toMatchObject({ piece_type: 'حلق', description_ar: 'حلق', description_en: 'Earring' });
  await expect.poll(() => calls.some(c => c.method === 'POST' && /piece_movements/.test(c.url) && (c.body || '').includes('النوع: عقد ← حلق'))).toBe(true);
});
