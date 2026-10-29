// Daily box: tapping an automatic row (invoice / voucher) asks «فتح الحركة» or «ربط الحركة»;
// linking only sets the shared link_group, so the two rows take the same colour.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('an invoice row can be linked to another row, or opened', async ({ page }) => {
  const now = new Date().toISOString();
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    daily_cash_log: [
      { id: 'inv1', store_id: STORE, direction: 'out', amount: 300, currency: 'AED', operation_type: 'فيزا — مبيعات لـ أحمد', bank_invoice_id: 'i9', created_at: now },
      { id: 'man1', store_id: STORE, direction: 'in', amount: 300, currency: 'AED', operation_type: 'تحويل من البنك', created_at: now }],
  } });
  await page.goto('/daily-cashbox-ar.html');
  await page.waitForFunction(() => typeof allEntries !== 'undefined' && allEntries.length === 2);
  await page.locator('[data-entry="inv1"]').click();
  await expect(page.locator('#autoRowModal')).not.toHaveClass(/\bhidden\b/);
  await page.selectOption('#autoRowLinkSelect', 'man1');
  await page.locator('#autoRowModal button', { hasText: 'حفظ الربط' }).click();
  await expect.poll(() => calls.filter(c => c.method === 'PATCH' && /daily_cash_log/.test(c.url)).length).toBe(2);
  const patches = calls.filter(c => c.method === 'PATCH' && /daily_cash_log/.test(c.url));
  const groups = patches.map(c => JSON.parse(c.body).link_group);
  expect(groups[0]).toBe('lnk_inv1');
  expect(groups[1]).toBe('lnk_inv1');
  expect(patches.every(c => Object.keys(JSON.parse(c.body)).join() === 'link_group')).toBe(true);
  // «فتح الحركة» still goes to the invoice
  await page.locator('[data-entry="inv1"]').click();
  await page.locator('#autoRowModal button', { hasText: 'فتح الحركة' }).click();
  await page.waitForURL(/invoice-print-ar\.html\?id=i9/);
});
