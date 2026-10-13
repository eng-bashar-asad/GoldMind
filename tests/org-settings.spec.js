// Multi-branch 1.2: legal data is edited on the organization, owner only.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const ORG = 'org-1';
function setup(page, { owner, branches = 1 }) {
  return install(page, {
    db: {
      stores: [{ id: STORE, name: 'محل', currency: 'AED', organization_id: ORG, tax_number: 'OLD', license_number: 'L-1' }],
      organizations: [{ id: ORG, name: 'محل', primary_store_id: STORE, tax_number: '100099655000003', legal_name: 'شركة الاختبار ذ.م.م', emirate_code: 'SHJ' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: owner ? 'owner' : 'staff', permissions: { edit_settings: true } }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    },
    rpc: {
      is_org_owner: () => ({ body: owner }),
      get_branch_count: () => ({ body: branches }),
    },
  });
}

test('owner edits organization data and it is saved to the organization', async ({ page }) => {
  const calls = await setup(page, { owner: true });
  await page.goto('/company-settings-ar.html');
  await page.locator('#org-section summary').click();
  await expect(page.locator('#store-tax')).toHaveValue('100099655000003'); // from the organization, not the store copy
  await expect(page.locator('#store-emirate')).toHaveValue('SHJ');
  await expect(page.locator('#org-readonly-note')).toHaveClass(/\bhidden\b/);
  await expect(page.locator('#branch-emirate-wrap')).toHaveClass(/\bhidden\b/); // single branch
  await page.locator('#store-tax').fill('100099655000099');
  await page.locator('#save-btn, button:has-text("حفظ البيانات")').first().click();
  await expect.poll(() => calls.find(c => c.method === 'PATCH' && c.name === 'organizations')).toBeTruthy();
  const orgPatch = JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'organizations').body);
  expect(orgPatch.tax_number).toBe('100099655000099');
  const storePatch = JSON.parse(calls.find(c => c.method === 'PATCH' && c.name === 'stores').body);
  expect(storePatch).not.toHaveProperty('tax_number'); // legal data no longer written to the branch
  expect(storePatch.license_number).toBe('L-1');
});

test('non-owner sees organization data read-only; branch emirate shows with several branches', async ({ page }) => {
  const calls = await setup(page, { owner: false, branches: 2 });
  await page.goto('/company-settings-ar.html');
  await page.locator('#org-section summary').click();
  await expect(page.locator('#org-readonly-note')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#store-tax')).toBeDisabled();
  await expect(page.locator('#branch-emirate-wrap')).not.toHaveClass(/\bhidden\b/);
  await page.locator('button:has-text("حفظ البيانات")').first().click();
  await expect.poll(() => calls.some(c => c.method === 'PATCH' && c.name === 'stores')).toBe(true);
  expect(calls.some(c => c.method === 'PATCH' && c.name === 'organizations')).toBe(false);
});
