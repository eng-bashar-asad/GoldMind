// Zircon weight: label symbol Z, designer option, saved on the piece.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('label prints Z:x.xxg for the zircon field, and nothing when empty', async ({ page }) => {
  await page.setContent('<html><body></body></html>');
  await page.addScriptTag({ path: require('path').join(__dirname, '..', 'zebra-rfid.js') });
  const zpl = await page.evaluate(() => {
    const fields = [{ id: 'z', content_type: 'zircon_carat', column_num: 1, row_order: 1, font_size: 20 }];
    return [
      GMZebra.buildBarcodeZPLFromFields({ fields, values: { zirconCarat: '0.50' } }),
      GMZebra.buildBarcodeZPLFromFields({ fields, values: { zirconCarat: '' } }),
    ];
  });
  expect(zpl[0]).toContain('Z:0.50g');
  expect(zpl[1]).not.toContain('Z:');
});

test('barcode designer offers the zircon field', async ({ page }) => {
  await install(page, {
    db: {
      stores: [{ id: STORE, name: 'محل' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      zebra_label_fields: [],
    },
  });
  await page.goto('/zebra-label-designer-ar.html');
  await page.waitForFunction(() => typeof showAddForm === 'function');
  await page.evaluate(() => showAddForm(1));
  await expect(page.locator('#add-type-1 option[value="zircon_carat"]')).toHaveText('وزن الزيركون Z (غرام)');
});

test('add-piece page shows the zircon field', async ({ page }) => {
  await install(page, { generic: true });
  await page.goto('/inventory-add.html');
  await expect(page.locator('#zircon-carat')).toBeVisible();
});
