// Decision 13: piece barcodes run on the head office's counter; other branches see them read-only.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

function setup(page, counter) {
  return install(page, {
    db: {
      stores: [{ id: STORE, name: 'فرع', currency: 'AED', organization_id: 'org-1', piece_barcode_prefix_gold: 'G', next_piece_seq_gold: 7 }],
      organizations: [{ id: 'org-1', name: 'المنشأة', primary_store_id: 'hq' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: { edit_settings: true } }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    },
    rpc: { is_org_owner: () => ({ body: false }), get_branch_count: () => ({ body: 2 }), barcode_counter_store: () => ({ body: counter }) },
  });
}

test('a branch that is not the head office: barcode fields locked and not saved', async ({ page }) => {
  const calls = await setup(page, 'hq');
  await page.goto('/company-settings-ar.html');
  await expect(page.locator('#barcode-hq-note')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#gold-prefix-input')).toBeDisabled();
  await expect(page.locator('#reset-gold-seq-btn')).toBeDisabled();
  await expect(page.locator('#next-gold-piece-preview')).toHaveText('—');
  await page.locator('button:has-text("حفظ البيانات")').first().click();
  await expect.poll(() => calls.find(c => c.method === 'PATCH' && c.name === 'stores')).toBeTruthy();
  expect(JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'stores').body)).not.toHaveProperty('piece_barcode_prefix_gold');
});

test('the head office keeps editing and saving its barcode prefix', async ({ page }) => {
  const calls = await setup(page, STORE);
  await page.goto('/company-settings-ar.html');
  await expect(page.locator('#next-gold-piece-preview')).toHaveText('G7');
  await expect(page.locator('#barcode-hq-note')).toHaveClass(/\bhidden\b/);
  await expect(page.locator('#gold-prefix-input')).toBeEnabled();
  await page.locator('button:has-text("حفظ البيانات")').first().click();
  await expect.poll(() => calls.find(c => c.method === 'PATCH' && c.name === 'stores')).toBeTruthy();
  expect(JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'stores').body).piece_barcode_prefix_gold).toBe('G');
});
