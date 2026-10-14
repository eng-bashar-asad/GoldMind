// Search result in the daily cash box opens THAT day (not today) and highlights the entry.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('search result opens its own day and highlights the entry', async ({ page }) => {
  const old = new Date(); old.setDate(old.getDate() - 5); old.setHours(12, 0, 0, 0);
  const pad = n => String(n).padStart(2, '0');
  const oldStr = old.getFullYear() + '-' + pad(old.getMonth() + 1) + '-' + pad(old.getDate());
  await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    daily_cash_log: [
      { id: 'old1', store_id: STORE, direction: 'in', amount: 700, currency: 'AED', operation_type: 'دفعة من أحمد', created_at: old.toISOString() },
      { id: 'now1', store_id: STORE, direction: 'out', amount: 5, currency: 'AED', operation_type: 'ضيافة', created_at: new Date().toISOString() }],
  } });
  await page.goto('/daily-cashbox-ar.html');
  await page.waitForFunction(() => typeof allEntries !== 'undefined' && allEntries.length === 2);
  await page.locator('button', { hasText: 'بحث بالحركات' }).click();
  await page.fill('#searchKeywordInput', 'أحمد');
  await page.locator('#searchPanel button', { hasText: 'بحث' }).click();
  const result = page.locator('#searchResults a').first();
  await expect(result).toHaveAttribute('href', `daily-cashbox-ar.html?date=${oldStr}&entry=old1`);
  await result.click();
  await page.waitForURL(/entry=old1/);
  await expect(page.locator('#entries-heading')).not.toHaveText('عمليات اليوم');
  const cell = page.locator('[data-entry="old1"]');
  await expect(cell).toBeVisible();
  await expect(cell).toHaveCSS('outline-style', 'solid');
  await expect(page.locator('[data-entry="now1"]')).toHaveCount(0); // today's entry is not on that day
});
