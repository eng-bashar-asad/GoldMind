// The invoice can be fixed to A5 (or A4) per device: the printed page takes that size and the A5 layout.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('A5 choice switches to the A5 layout and is remembered', async ({ page }) => {
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'x', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.goto('/invoice-print-ar.html?id=x');
  await page.selectOption('#paper-sel', 'A5');
  // the page size is left to the print dialog (forcing it broke printing on Windows)
  await expect(page.locator('#gm-page-size')).toHaveCount(0);
  await expect(page.locator('body')).toHaveClass(/gm-paper-A5/);
  await page.reload();
  await expect(page.locator('#paper-sel')).toHaveValue('A5');
  await page.selectOption('#paper-sel', 'auto');
  await expect(page.locator('body')).not.toHaveClass(/gm-paper-A5/);
});
