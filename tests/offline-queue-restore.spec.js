// Offline sales: the queue is also kept in IndexedDB, so unsent sales survive a cleared localStorage;
// offline, the badge says how old the device's data copy is.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
});

test('a queued sale comes back from IndexedDB after localStorage is cleared', async ({ page, context }) => {
  await install(page, { db: db() });
  await page.goto('/customers-ar.html');
  await page.waitForFunction(() => typeof gmSaveQueue === 'function');
  await page.evaluate(async () => {
    gmSaveQueue([{ payload: { client_ref: 'r1', items: [{ price: 10 }] }, meta: {}, queued_at: new Date().toISOString(), status: 'failed', error: 'x' }]);
    await new Promise(r => setTimeout(r, 300));
    localStorage.removeItem('gm_offline_sales');
  });
  await page.reload();
  await expect(page.locator('#gm-offline-badge')).toContainText('لم تُرحَّل');
  expect(await page.evaluate(() => gmQueue().length)).toBe(1);
});

test('offline badge shows how old the data copy is', async ({ page, context }) => {
  await install(page, { db: db() });
  await page.goto('/customers-ar.html');
  await page.waitForFunction(() => typeof gmRenderOfflineBadge === 'function');
  await page.evaluate(() => localStorage.setItem('gm_snapshot_at', String(Date.now() - 3600e3)));
  await context.setOffline(true);
  await page.evaluate(() => window.dispatchEvent(new Event('offline')));
  await expect(page.locator('#gm-offline-badge')).toContainText('البيانات محدّثة حتى');
  await context.setOffline(false);
});
