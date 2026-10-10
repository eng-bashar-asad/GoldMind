const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

test('a code error on a page is reported once to client_errors', async ({ page }) => {
  const calls = await install(page, { generic: true });
  await page.goto('/settings-ar.html');
  await page.evaluate(() => { setTimeout(() => { throw new Error('boom test'); }); setTimeout(() => { throw new Error('boom test'); }); });
  await expect.poll(() => calls.filter(c => c.name === 'client_errors' && c.method === 'POST').length).toBe(1);
  const body = JSON.parse(calls.find(c => c.name === 'client_errors').body);
  expect(body).toMatchObject({ message: expect.stringContaining('boom test'), page: 'settings-ar.html' });
  await page.waitForTimeout(300);
  expect(calls.filter(c => c.name === 'client_errors').length).toBe(1); // same message not sent twice
});

test('admin panel lists reported errors grouped by message', async ({ page }) => {
  const now = new Date().toISOString();
  await install(page, {
    db: {
      client_errors: [
        { created_at: now, page: 'new-sale-ar.html', message: 'x is not defined', stores: { name: 'محل أ' } },
        { created_at: now, page: 'new-sale-ar.html', message: 'x is not defined', stores: { name: 'محل ب' } },
        { created_at: now, page: 'ledger-ar.html', message: 'boom', stores: null }
      ],
      user_profiles: [{ id: '22222222-2222-2222-2222-222222222222', privacy_accepted_at: '2026-01-01' }]
    },
    rpc: { is_platform_admin: () => ({ body: true }), admin_list_stores: () => ({ body: [] }), admin_list_support_requests: () => ({ body: [] }) }
  });
  await page.goto('/admin-panel-ar.html');
  await expect(page.locator('#errors-badge')).toHaveText('2');
  await page.click('#tabErrors');
  await expect(page.locator('#errors-list details')).toHaveCount(2);
  await expect(page.locator('#errors-list')).toContainText('2 مرة');
});
