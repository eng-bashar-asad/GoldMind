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

test('branches page no longer creates companies, it links to the new-company page', async ({ page }) => {
  await setup(page);
  await page.goto('/branches-ar.html');
  await expect(page.locator('#new-company-hint')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#new-company-hint a')).toHaveAttribute('href', 'company-new-ar.html');
  await expect(page.locator('#add-company-btn')).toHaveCount(0);
});

test('new company page: required fields and terms, then register_new_company + country/currency/legal data', async ({ page }) => {
  const calls = await install(page, {
    db: {
      stores: [{ id: STORE, name: 'المحل الرئيسي', organization_id: ORG }, { id: 'new-co', name: 'شركة ثانية', organization_id: 'org-2' }],
      organizations: [{ id: ORG, name: 'المنشأة', primary_store_id: STORE }, { id: 'org-2', name: 'شركة ثانية', primary_store_id: 'new-co' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    },
    rpc: { register_new_company: () => ({ body: 'new-co' }) },
  });
  await page.goto('/company-new-ar.html');
  await page.click('#submit-btn');
  await expect(page.locator('#f-name')).toHaveClass(/border-error/);
  await page.fill('#f-name', 'شركة ثانية');
  await page.selectOption('#f-country', 'SY');
  await expect(page.locator('#f-currency')).toHaveValue('USD');
  await page.fill('#f-trn', '100200300400003');
  await page.click('#submit-btn');
  await expect(page.locator('#msg')).toContainText('الشروط');
  expect(calls.some(c => c.name === 'register_new_company')).toBe(false);
  await page.check('#f-terms');
  await page.click('#submit-btn');
  await expect(page.locator('#msg')).toContainText('شركة ثانية');
  await expect(page.locator('#msg button')).toHaveText('انتقل إلى الشركة الجديدة');
  expect(JSON.parse(calls.find(c => c.name === 'register_new_company').body)).toEqual({ company_name: 'شركة ثانية', terms_accepted: true, terms_version: '1.2' });
  expect(JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'stores').body)).toEqual({ country: 'SY', currency: 'USD' });
  expect(JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'organizations').body)).toEqual({ country: 'SY', tax_number: '100200300400003' });
});

test('switch page groups branches under their company', async ({ page }) => {
  await install(page, {
    db: {
      stores: [{ id: STORE, organization_id: ORG }, { id: 'b2', organization_id: ORG }, { id: 'c2', organization_id: 'org-2' }],
      organizations: [{ id: ORG, name: 'المنشأة', legal_name: 'الخياط للمجوهرات' }, { id: 'org-2', name: 'شركة سوريا' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    },
    rpc: { my_stores: () => ({ body: [{ store_id: STORE, store_name: 'الشارقة', role: 'owner' }, { store_id: 'b2', store_name: 'ديرة', role: 'owner' }, { store_id: 'c2', store_name: 'دمشق', role: 'owner' }] }) },
  });
  await page.goto('/switch-branch-ar.html');
  await expect(page.locator('#stores-list section')).toHaveCount(2);
  await expect(page.locator('#stores-list section').first()).toContainText('الخياط للمجوهرات — 2 فروع');
  await expect(page.locator('#stores-list section').nth(1)).toContainText('دمشق');
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
