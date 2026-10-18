// Multi-branch 1.4: optional branch code in front of invoice numbers, set in company settings.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const ORG = 'org-1';
function setup(page, { branches, store = {} }) {
  return install(page, {
    db: {
      stores: [{ id: STORE, name: 'محل', currency: 'AED', organization_id: ORG, branch_code: null, ...store }],
      organizations: [{ id: ORG, name: 'محل', primary_store_id: STORE }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: { edit_settings: true } }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    },
    rpc: { is_org_owner: () => ({ body: true }), get_branch_count: () => ({ body: branches }) },
  });
}

test('several branches: the code is typed in capitals and saved on the branch', async ({ page }) => {
  const calls = await setup(page, { branches: 2 });
  await page.goto('/company-settings-ar.html');
  await page.locator('details:has(#store-license) summary').click();
  await expect(page.locator('#branch-code-wrap')).not.toHaveClass(/\bhidden\b/);
  await page.locator('#store-branch-code').fill('dxb1');
  await expect(page.locator('#store-branch-code')).toHaveValue('DXB');
  await page.locator('button:has-text("حفظ البيانات")').first().click();
  await expect.poll(() => calls.find(c => c.method === 'PATCH' && c.name === 'stores')).toBeTruthy();
  expect(JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'stores').body).branch_code).toBe('DXB');
});

test('one branch: the field stays hidden and an empty code is saved as none', async ({ page }) => {
  const calls = await setup(page, { branches: 1 });
  await page.goto('/company-settings-ar.html');
  await expect(page.locator('#branch-code-wrap')).toHaveClass(/\bhidden\b/);
  await page.locator('button:has-text("حفظ البيانات")').first().click();
  await expect.poll(() => calls.find(c => c.method === 'PATCH' && c.name === 'stores')).toBeTruthy();
  expect(JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'stores').body).branch_code).toBeNull();
});

test('before the column exists nothing about the code is sent', async ({ page }) => {
  const calls = await install(page, {
    db: {
      stores: [{ id: STORE, name: 'محل', currency: 'AED', organization_id: ORG }],
      organizations: [{ id: ORG, name: 'محل', primary_store_id: STORE }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: { edit_settings: true } }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    },
    rpc: { is_org_owner: () => ({ body: true }), get_branch_count: () => ({ body: 2 }) },
  });
  await page.goto('/company-settings-ar.html');
  await expect(page.locator('#branch-code-wrap')).toHaveClass(/\bhidden\b/);
  await page.locator('button:has-text("حفظ البيانات")').first().click();
  await expect.poll(() => calls.find(c => c.method === 'PATCH' && c.name === 'stores')).toBeTruthy();
  expect(JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'stores').body)).not.toHaveProperty('branch_code');
});
