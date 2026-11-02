// Side menu extras (Bashar 2026-11-02): light/dark choice at the top, favourites, Ctrl+K search.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const db = { stores: [{ id: STORE, name: 'محل' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  customers: [{ id: 'c1', store_id: STORE, name: 'تامر الحسن', phone: '050' }], traders: [], pieces: [{ id: 'p1', store_id: STORE, barcode: '000412', status: 'available', weight_grams: 5 }] };

test('menu look: dark by default on a phone, light chosen from the top and kept', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await install(page, { db });
  await page.goto('/inventory-list-ar.html');
  await expect(page.locator('#gmNav')).not.toHaveClass(/gn-light/);
  await page.evaluate(() => openNavDrawer());
  await page.click('#gmNav .gn-style button[data-st="light"]');
  await expect(page.locator('#gmNav')).toHaveClass(/gn-light/);
  await page.reload();
  await expect(page.locator('#gmNav')).toHaveClass(/gn-light/);
});

test('menu look: light glass by default on a computer', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await install(page, { db });
  await page.goto('/inventory-list-ar.html');
  await expect(page.locator('#gmNav')).toHaveClass(/gn-light/);
  await expect(page.locator('#gmNav .gn-style button[data-st="light"]')).toHaveAttribute('aria-checked', 'true');
});

test('favourites: star a page, it shows on top; Ctrl+K finds pages, customers and a barcode', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await install(page, { db });
  await page.goto('/inventory-list-ar.html');
  const favs = page.locator('#gmNav .gn-favlist a.gn-a');
  await expect(favs).toHaveCount(3);
  await page.click('#gmNav .gn-favedit');
  await page.click('#gmNav .gn-h:has-text("المالية")');
  await page.click('#gmNav .gn-g a.gn-a[href="gold-price-ar.html"] .gn-star');
  await expect(favs).toHaveCount(4);
  await expect(page.locator('#gmNav .gn-favlist')).toContainText('سعر الذهب');

  await page.keyboard.press('Control+k');
  const pal = page.locator('.gm-pal-ov');
  await expect(pal).toHaveClass(/open/);
  await expect(page.locator('.gm-pal-in input')).toBeFocused();
  await page.keyboard.type('الجرد');
  await expect(pal.locator('.gm-pal-row').first()).toContainText('الجرد');
  await page.fill('.gm-pal-in input', 'تامر');
  await expect(pal).toContainText('تامر الحسن');
  await page.fill('.gm-pal-in input', '000412');
  await expect(pal.locator('a[href="piece-edit-ar.html?id=p1"]')).toHaveCount(1);
  await page.keyboard.press('Escape');
  await expect(pal).not.toHaveClass(/open/);
});

test('glass pages: on by default with the emblem background; «عادية» turns them off and is kept', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await install(page, { db });
  await page.goto('/inventory-list-ar.html');
  await expect(page.locator('html')).toHaveClass(/gm-glass/);
  await expect(page.locator('#gmGlassBg svg').first()).toBeAttached();
  await page.evaluate(() => openNavDrawer());
  await page.click('#gmNav .gn-pages button[data-gl="0"]');
  await expect(page.locator('html')).not.toHaveClass(/gm-glass/);
  await page.reload();
  await expect(page.locator('html')).not.toHaveClass(/gm-glass/);
  await expect(page.locator('#gmNav .gn-pages button[data-gl="0"]')).toHaveAttribute('aria-checked', 'true');
});
