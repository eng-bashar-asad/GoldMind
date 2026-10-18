// Multi-branch 2.4: transfer voucher between branches; the receiving branch confirms.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const branches = [{ id: STORE, name: 'المستودع', can_open_invoices: true }, { id: 'b2', name: 'فرع ديرة', can_open_invoices: true }];
const base = extra => ({
  stores: [{ id: STORE, name: 'المستودع', currency: 'AED' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  branch_transfers: [], ...extra,
});

test('send: scanned barcodes go to the chosen branch in one voucher', async ({ page }) => {
  const calls = await install(page, { db: base(), rpc: { org_branches: () => ({ body: branches }), send_branch_transfer: () => ({ body: { id: 'tr1', transfer_number: 'TRF-000001', items: 2 } }) } });
  page.on('dialog', d => d.accept());
  await page.goto('/branch-transfers-ar.html?tab=send');
  await page.selectOption('#to-branch', 'b2');
  for (const bc of ['G0101', 'G0102', 'G0101']) { await page.fill('#send-barcode', bc); await page.press('#send-barcode', 'Enter'); }
  await expect(page.locator('#send-list li')).toHaveCount(2); // duplicates ignored
  await page.click('#send-btn');
  await expect(page.locator('#msg')).toContainText('TRF-000001');
  expect(JSON.parse(calls.find(c => c.name === 'send_branch_transfer').body)).toEqual({ p_from: STORE, p_to: 'b2', p_barcodes: ['G0101', 'G0102'], p_notes: null });
});

test('incoming: scanning a piece confirms it; the button confirms the rest', async ({ page }) => {
  const calls = await install(page, {
    db: base({ branch_transfers: [{ id: 'tr9', transfer_number: 'TRF-000009', from_store_id: 'b2', to_store_id: STORE, status: 'in_transit', created_at: '2026-10-19T08:00:00Z',
      items: [{ id: 'i1', barcode: 'G0201', karat: 18, weight_grams: 5, received_at: null }, { id: 'i2', barcode: 'G0202', karat: 18, weight_grams: 6, received_at: null }] }] }),
    rpc: { org_branches: () => ({ body: branches }), receive_branch_transfer: () => ({ body: { received: 1, remaining: 1 } }) },
  });
  page.on('dialog', d => d.accept());
  await page.goto('/branch-transfers-ar.html');
  await expect(page.locator('#tab-in')).toContainText('TRF-000009');
  await expect(page.locator('#tab-in')).toContainText('من فرع ديرة');
  await page.fill('.recv-scan', 'G0201');
  await page.press('.recv-scan', 'Enter');
  await expect.poll(() => calls.filter(c => c.name === 'receive_branch_transfer').length).toBe(1);
  expect(JSON.parse(calls.find(c => c.name === 'receive_branch_transfer').body)).toEqual({ p_transfer: 'tr9', p_barcodes: ['G0201'] });
  await page.click('button:has-text("تأكيد استلام كل القطع")');
  await expect.poll(() => calls.filter(c => c.name === 'receive_branch_transfer').length).toBe(2);
  expect(JSON.parse(calls.filter(c => c.name === 'receive_branch_transfer')[1].body)).toEqual({ p_transfer: 'tr9', p_barcodes: null });
});

test('single branch: nothing to transfer', async ({ page }) => {
  await install(page, { db: base(), rpc: { org_branches: () => ({ body: [branches[0]] }) } });
  await page.goto('/branch-transfers-ar.html');
  await expect(page.locator('#no-branches')).not.toHaveClass(/\bhidden\b/);
});
