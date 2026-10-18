// Multi-branch 2.3: one trader account for the organization; another branch's movements are shown, not editable here.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('trader from another branch: balance includes its movements, which are labelled and locked', async ({ page }) => {
  await install(page, {
    db: {
      stores: [{ id: STORE, name: 'فرع ب', currency: 'AED' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      traders: [{ id: 't1', store_id: 'branch-a', name: 'حمدي الخياط' }],
      trader_movements: [
        { id: 'm1', store_id: 'branch-a', trader_id: 't1', movement_type: 'debt_increase', source: 'opening_balance', weight_grams: 0, gold_24k_equivalent: 0, fab_fee_amount: 500, notes: 'رصيد سابق', created_at: '2026-09-01T10:00:00Z' },
      ],
      cash_movements: [],
    },
    rpc: { org_branches: () => ({ body: [{ id: STORE, name: 'فرع ب', can_open_invoices: true }, { id: 'branch-a', name: 'فرع أ', can_open_invoices: true }] }) },
  });
  await page.goto('/ledger-ar.html?trader=t1');
  await expect(page.locator('body')).toContainText('حمدي الخياط');
  await expect(page.locator('body')).toContainText('سُجّلت في فرع أ');
  await expect(page.locator('button[onclick^="deleteOpeningBalanceMovement"]').first().locator('xpath=..')).toHaveClass(/\bhidden\b/);
});
