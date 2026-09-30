// The same full side menu on every page (phone button next to the back arrow), and on the laptop home.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const db = (role, permissions) => ({ stores: [{ id: STORE, name: 'x', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role, permissions, full_name: 'B' }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], staff_presence: [] });

for (const p of ['inventory-list-ar.html', 'piece-edit-ar.html', 'invoice-print-ar.html', 'financial-report-ar.html', 'daily-cashbox-ar.html']) {
  test('menu on ' + p, async ({ page }) => {
    const errs = []; page.on('pageerror', e => errs.push(e.message));
    await install(page, { db: db('owner', {}) });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/' + p);
    await page.waitForSelector('.gm-nav-btn', { state: 'attached' });
    await page.evaluate(() => document.querySelector('.gm-nav-btn').click());
    await expect(page.locator('#gmNav')).toHaveClass(/open/);
    await expect(page.locator('#gmNav a.gn-a')).toHaveCount(await page.locator('#gmNav a.gn-a').count());
    expect(await page.locator('#gmNav a.gn-a').count()).toBeGreaterThan(40);
    await page.keyboard.press('Escape');
    await expect(page.locator('#gmNav')).not.toHaveClass(/open/);
    expect(errs).toEqual([]);
  });
}

test('staff without permissions: reports hidden in menu', async ({ page }) => {
  await install(page, { db: db('staff', { view_inventory: true }) });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/inventory-list-ar.html');
  await page.waitForTimeout(1500);
  await expect(page.locator('#gmNav a[href="profit-report-ar.html"]')).toBeHidden();
  await expect(page.locator('#gmNav a[href="inventory-list-ar.html"]')).toHaveCount(1);
});

test('laptop home: full sidebar + who is online', async ({ page }) => {
  await install(page, { db: db('owner', {}) });
  await page.setViewportSize({ width: 1366, height: 800 });
  await page.goto('/index-ar.html');
  await expect(page.locator('.dsk-nav-scroll a[href="financial-report-ar.html"]')).toHaveCount(1);
  await expect(page.locator('#gmOnlineBtnDsk')).not.toHaveClass(/\bhidden\b/);
});
