// Home: gold candles box (5m / 15m / 1h, remembered) and sales charts (owner / view_reports only).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const ago = d => new Date(Date.now() - d * 86400000).toISOString();
const db = (role, permissions) => ({
  stores: [{ id: STORE, name: 'x', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role, permissions, full_name: 'بشار' }, { id: 's2', store_id: STORE, role: 'staff', full_name: 'حجازي' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  invoices: [
    { id: 'i1', store_id: STORE, type: 'sale', status: 'paid', total_amount: 3000, salesperson_id: 's2', created_by: STAFF, currency: 'USD', created_at: ago(1) },
    { id: 'i2', store_id: STORE, type: 'sale', status: 'paid', total_amount: 1000, salesperson_id: STAFF, created_by: STAFF, currency: 'USD', created_at: ago(2) },
    { id: 'i3', store_id: STORE, type: 'sale', status: 'cancelled', total_amount: 9999, salesperson_id: STAFF, created_by: STAFF, currency: 'USD', created_at: ago(2) },
    { id: 'i4', store_id: STORE, type: 'sale', status: 'paid', total_amount: 2000, salesperson_id: STAFF, created_by: STAFF, currency: 'USD', created_at: ago(9) },
  ],
});

test('computer: sales charts for the owner — 7 days vs the week before, sellers ranked', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await install(page, { generic: true, db: db('owner', {}) });
  await page.goto('/index-ar.html');
  const box = page.locator('#dskSalesChartPanel [data-gmc-sales]');
  await expect(box).not.toHaveClass(/\bhidden\b/);
  await expect(box.locator('.gmc-kpi b')).toHaveText('4,000');
  await expect(box.locator('.gmc-chg')).toContainText('100%');
  await expect(box.locator('.gmc-bar')).toHaveCount(30);
  await expect(box.locator('.gmc-srow').first()).toContainText('حجازي');
  await expect(box.locator('.gmc-srow').nth(1)).toContainText('بشار');
});

test('gold box: candle size buttons, the choice is remembered', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await install(page, { generic: true, db: db('owner', {}) });
  await page.goto('/index-ar.html');
  const seg = page.locator('#dskGoldChartPanel .gmc-seg');
  await expect(seg.locator('button')).toHaveCount(3);
  await seg.locator('button', { hasText: 'ساعة' }).click();
  await expect(seg.locator('button', { hasText: 'ساعة' })).toHaveAttribute('aria-pressed', 'true');
  expect(await page.evaluate(() => localStorage.getItem('gm_gold_chart_tf'))).toBe('60');
});

test('staff without view_reports: no sales charts', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await install(page, { generic: true, db: db('staff', { view_inventory: true }) });
  await page.goto('/index-ar.html');
  await page.waitForTimeout(1500);
  await expect(page.locator('[data-gmc-sales]').last()).toHaveClass(/\bhidden\b/);
});
