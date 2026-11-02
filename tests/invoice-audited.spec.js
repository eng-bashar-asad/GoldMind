// «مدقق» on the invoices list: the owner checks it (rpc set_invoice_audited); an audited invoice hides its edit actions.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const T = new Date().toISOString(); // staff without 'view_past_days' see today only
const base = (role, audited) => ({
  stores: [{ id: STORE, name: 'x', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role, permissions: {}, full_name: 'ب' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  repair_tickets: [], trader_movements: [], stock_vouchers: [], customer_debts: [], invoice_items: [],
  invoices: [{ id: 'i1', store_id: STORE, invoice_number: 'INV-26', type: 'sale', status: 'paid', total_amount: 100, currency: 'USD', created_at: T, audited_at: audited ? T : null }]
});

test('owner checks «مدقق» from the list', async ({ page }) => {
  const calls = [];
  await install(page, { generic: true, db: base('owner', false), rpc: { set_invoice_audited: a => { calls.push(a); return { status: 200, body: T }; } } });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/invoices-list-ar.html');
  const box = page.locator('input[data-audit="i1"]');
  await expect(box).not.toBeChecked();
  await box.check();
  await expect.poll(() => calls.length).toBe(1);
  expect(calls[0]).toEqual({ p_invoice: 'i1', p_on: true });
  await expect(page.locator('input[data-audit="i1"]')).toBeChecked();
  await expect(page).toHaveURL(/invoices-list-ar\.html/); // the row click did not open the invoice
});

test('staff without the permission cannot uncheck; the invoice page shows the lock', async ({ page }) => {
  await install(page, { generic: true, db: base('staff', true) });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/invoices-list-ar.html');
  await expect(page.locator('input[data-audit="i1"]')).toBeChecked();
  await expect(page.locator('input[data-audit="i1"]')).toBeDisabled();
  await page.goto('/invoice-print-ar.html?id=i1');
  await expect(page.locator('#audited-banner')).not.toHaveClass(/\bhidden\b/);
  await expect(page.locator('#edit-invoice-btn')).toHaveClass(/\bhidden\b/);
  await expect(page.locator('#cancel-invoice-btn')).toHaveClass(/\bhidden\b/);
});
