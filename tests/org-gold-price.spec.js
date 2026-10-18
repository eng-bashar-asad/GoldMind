// Multi-branch 2.2: one gold price for the organization; a branch may keep its own.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

function setup(page, { own = false, branches = 2, rpc = {} } = {}) {
  return install(page, {
    db: {
      stores: [{ id: STORE, name: 'فرع', currency: 'AED', last_gold_ounce_price: 4000, last_gold_ounce_rate: 3.6725, own_gold_price: own }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'staff', permissions: { manage_gold_price: true } }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      gold_prices: [{ store_id: STORE, karat: 24, price_per_gram: 472.3, updated_at: '2026-10-18T10:00:00Z' }],
    },
    rpc: { org_branches: () => ({ body: Array.from({ length: branches }, (_, i) => ({ id: i ? 'b' + i : STORE, name: 'فرع ' + i, can_open_invoices: true })) }), ...rpc },
  });
}

test('several branches: the organization-price note shows and the own-price switch calls the server', async ({ page }) => {
  const calls = await setup(page, { rpc: { set_branch_own_gold_price: () => ({ body: null }) } });
  await page.goto('/gold-price-ar.html');
  await expect(page.locator('#orgPriceBox')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#orgPriceNote')).toContainText('موحّد للمنشأة');
  await page.check('#ownPrice');
  await expect.poll(() => calls.find(c => c.name === 'set_branch_own_gold_price')).toBeTruthy();
  expect(JSON.parse(calls.find(c => c.name === 'set_branch_own_gold_price').body)).toEqual({ p_store: STORE, p_own: true });
  await expect(page.locator('#orgPriceNote')).toContainText('هذا الفرع فقط');
});

test('one branch: no organization-price box', async ({ page }) => {
  await setup(page, { branches: 1 });
  await page.goto('/gold-price-ar.html');
  await expect(page.locator('#price24')).not.toHaveText('—');
  await expect(page.locator('#orgPriceBox')).toHaveClass(/\bhidden\b/);
});
