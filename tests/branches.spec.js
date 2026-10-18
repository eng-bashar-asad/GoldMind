// Multi-branch 1.5: add a branch to my organization, a new independent company, and the head office.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const ORG = 'org-1';
function setup(page, { owner = true, rpc = {}, headCol = true } = {}) {
  return install(page, {
    db: {
      stores: [{ id: STORE, name: 'المحل الرئيسي', organization_id: ORG, branch_code: 'DXB', created_at: '2026-01-01' },
               { id: 'b2', name: 'فرع ديرة', organization_id: ORG, branch_code: null, created_at: '2026-02-01' }],
      organizations: [{ id: ORG, name: 'المنشأة', primary_store_id: STORE, ...(headCol ? { head_office_store_id: STORE } : {}) }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: owner ? 'owner' : 'staff', permissions: {} }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    },
    rpc: { is_org_owner: () => ({ body: owner }), ...rpc },
  });
}

test('owner adds a branch: create_branch gets this store and the name, then offers to switch', async ({ page }) => {
  const calls = await setup(page, { rpc: { create_branch: () => ({ body: 'new-branch' }) } });
  await page.goto('/branches-ar.html');
  await expect(page.locator('#branches-list label')).toHaveCount(2);
  await page.click('#add-branch-btn');
  await expect(page.locator('#branch-name')).toHaveClass(/border-error/); // name required
  await page.fill('#branch-name', 'فرع الشارقة');
  await page.click('#add-branch-btn');
  await expect(page.locator('#msg')).toContainText('فرع الشارقة');
  const call = calls.find(c => c.name === 'create_branch');
  expect(JSON.parse(call.body)).toEqual({ p_from_store: STORE, p_name: 'فرع الشارقة' });
  await expect(page.locator('#msg button')).toHaveText('انتقل إليه الآن');
});

test('owner moves the head office to another branch', async ({ page }) => {
  const calls = await setup(page);
  await page.goto('/branches-ar.html');
  await expect(page.locator(`input[name="head-office"][value="${STORE}"]`)).toBeChecked();
  await page.check('input[name="head-office"][value="b2"]');
  await page.click('#save-head-btn');
  await expect.poll(() => calls.find(c => c.method === 'PATCH' && c.name === 'organizations')).toBeTruthy();
  expect(JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'organizations').body)).toEqual({ head_office_store_id: 'b2' });
});

test('new independent company needs the terms and uses register_new_company', async ({ page }) => {
  const calls = await setup(page, { rpc: { register_new_company: () => ({ body: 'new-co' }) } });
  await page.goto('/branches-ar.html');
  await page.fill('#company-name', 'شركة ثانية');
  await page.click('#add-company-btn');
  await expect(page.locator('#msg')).toContainText('الشروط');
  expect(calls.some(c => c.name === 'register_new_company')).toBe(false);
  await page.check('#company-terms');
  await page.click('#add-company-btn');
  await expect(page.locator('#msg')).toContainText('شركة ثانية');
  expect(JSON.parse(calls.find(c => c.name === 'register_new_company').body).terms_accepted).toBe(true);
});

test('not the owner: nothing to manage', async ({ page }) => {
  await setup(page, { owner: false });
  await page.goto('/branches-ar.html');
  await expect(page.locator('#not-owner')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#add-branch-section')).toHaveClass(/\bhidden\b/);
});

test('before the migration: branches listed, no head office choice', async ({ page }) => {
  await setup(page, { headCol: false });
  await page.goto('/branches-ar.html');
  await expect(page.locator('#branches-list label')).toHaveCount(2);
  await expect(page.locator('input[name="head-office"]')).toHaveCount(0);
  await expect(page.locator('#save-head-btn')).toHaveClass(/\bhidden\b/);
});
