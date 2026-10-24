// Computer home: «تخصيص الشاشة» hides / sizes boxes and saves to the account; quick-access icons drag with the mouse.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('layout panel hides and sizes boxes, saved on the account', async ({ page }) => {
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  } });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/index-ar.html');
  await page.click('#dskLayoutBtn');
  await expect(page.locator('#dskLayoutOverlay')).not.toHaveClass(/\bhidden\b/);
  await page.locator('#dskLayoutRows input[data-k="stock"]').uncheck();
  await expect(page.locator('a.dsk-stat[href="inventory-list-ar.html"]')).toHaveClass(/\bdsk-off\b/);
  await page.locator('#dskLayoutRows button[data-k="sales"][data-size="l"]').click();
  await expect(page.locator('#dskTodaySalesEl').locator('xpath=ancestor::div[contains(@class,"dsk-stat")][1]')).toHaveClass(/\bdsk-sz-l\b/);
  await expect.poll(() => calls.some(c => c.name === 'user_profiles' && c.method === 'PATCH' && /home_prefs/.test(c.body || ''))).toBe(true);
  await expect(page.locator('#dskActionStrip .dsk-action').first()).toHaveAttribute('draggable', 'true');
});
