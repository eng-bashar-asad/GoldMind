// Multi-branch 3.1: reports can cover all branches the user may see (same currency, report permission).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const branches = [{ id: STORE, name: 'الرئيسي', can_open_invoices: true }, { id: 'b2', name: 'فرع ديرة', can_open_invoices: true },
  { id: 'b3', name: 'فرع دمشق', can_open_invoices: true }, { id: 'b4', name: 'فرع بلا صلاحية', can_open_invoices: true }];
const inv = (id, store, total, type = 'sale') => ({ id, store_id: store, invoice_number: 'INV-' + id, type, status: 'paid', total_amount: total, vat_amount: 0, created_at: new Date().toISOString() });

async function setup(page) {
  await page.addInitScript(s => { try { localStorage.setItem('goldmind_active_store', s); } catch (e) { /* ignore */ } }, STORE);
  return install(page, {
    db: {
      stores: [{ id: STORE, name: 'الرئيسي', currency: 'AED', vat_rate: 5 }, { id: 'b2', name: 'فرع ديرة', currency: 'aed' },
        { id: 'b3', name: 'فرع دمشق', currency: 'USD' }, { id: 'b4', name: 'فرع بلا صلاحية', currency: 'AED' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} },
        { id: 's2', user_id: USER, store_id: 'b2', role: 'staff', permissions: { view_reports: true, view_profit_report: true } },
        { id: 's3', user_id: USER, store_id: 'b3', role: 'owner', permissions: {} },
        { id: 's4', user_id: USER, store_id: 'b4', role: 'staff', permissions: { view_reports: false } }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      invoices: [inv('1', STORE, 105), inv('2', 'b2', 210), inv('3', 'b3', 999), inv('4', 'b4', 777)],
      customers: [], traders: [],
    },
    rpc: { org_branches: () => ({ body: branches }) },
  });
}

test('tax statement: this branch by default, all permitted same-currency branches on demand', async ({ page }) => {
  await setup(page);
  await page.goto('/tax-report-ar.html');
  const sel = page.locator('#gm-branch-scope');
  await expect(sel.locator('option')).toHaveText(['كل الفروع', 'الرئيسي (هذا الفرع)', 'فرع ديرة']); // USD branch and no-permission branch left out
  await expect(page.locator('#sum-total-sales')).toHaveText('105.00');
  await sel.selectOption('all');
  await expect(page.locator('#sum-total-sales')).toHaveText('315.00');
  await expect(page.locator('#salesTaxList')).toContainText('فرع ديرة');
  await expect(page.locator('#scope-label')).toContainText('كل الفروع');
  expect(new URL(page.url()).searchParams.get('branch')).toBe('all');
  await page.reload();
  await expect(page.locator('#sum-total-sales')).toHaveText('315.00'); // kept in the URL
});

test('one branch only: no branch picker', async ({ page }) => {
  await install(page, {
    db: { stores: [{ id: STORE, name: 'الرئيسي', currency: 'AED', vat_rate: 5 }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }], invoices: [inv('1', STORE, 105)], customers: [], traders: [] },
    rpc: { org_branches: () => ({ body: [branches[0]] }) },
  });
  await page.goto('/tax-report-ar.html');
  await expect(page.locator('#sum-total-sales')).toHaveText('105.00');
  await expect(page.locator('#gm-branch-scope')).toHaveCount(0);
});

for (const [path, done] of [['/reports-ar.html', '#invoices-count'], ['/financial-report-ar.html', '#fr-body table'], ['/profit-report-ar.html', '#pr-sections div']]) {
  test(`${path}: all branches load without errors and tag the branch`, async ({ page }) => {
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    page.on('dialog', d => d.dismiss());
    await setup(page);
    await page.goto(path + '?branch=all');
    await expect(page.locator('#gm-branch-scope')).toHaveValue('all');
    await expect(page.locator(done).first()).toBeVisible();
    if (path === '/reports-ar.html') { await expect(page.locator('#invoices-count')).toHaveText('2'); await expect(page.locator('#invoices-tbody')).toContainText('فرع ديرة'); }
    if (path === '/financial-report-ar.html') await expect(page.locator('#fr-store')).toContainText('كل الفروع');
    expect(errors).toEqual([]);
  });
}
