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
  await page.click('button:has-text("تأكيد استلام كل ما في السند")');
  await expect.poll(() => calls.filter(c => c.name === 'receive_branch_transfer').length).toBe(2);
  expect(JSON.parse(calls.filter(c => c.name === 'receive_branch_transfer')[1].body)).toEqual({ p_transfer: 'tr9', p_barcodes: null });
});

test('scrap and cash: sent with the voucher, receiver confirms each line', async ({ page }) => {
  const calls = await install(page, {
    db: base({ branch_transfers: [{ id: 'tr5', transfer_number: 'TRF-000005', from_store_id: 'b2', to_store_id: STORE, status: 'in_transit', created_at: '2026-10-19T08:00:00Z',
      items: [{ id: 's1', transfer_id: 'tr5', kind: 'scrap', description: 'كسر 21', karat: 21, weight_grams: 15, received_at: null },
              { id: 'c1', transfer_id: 'tr5', kind: 'cash', description: 'نقد', amount: 500, received_at: null }] }] }),
    rpc: { org_branches: () => ({ body: branches }), send_branch_transfer: () => ({ body: { id: 'tr6', transfer_number: 'TRF-000006', items: 2 } }),
           receive_branch_transfer: () => ({ body: { received: 1, remaining: 1 } }) },
  });
  page.on('dialog', d => d.accept());
  await page.goto('/branch-transfers-ar.html');
  await expect(page.locator('.recv-scan')).toHaveCount(0); // nothing to scan: no pieces
  await page.click('#tab-in li:has-text("نقد") button');
  await expect.poll(() => calls.filter(c => c.name === 'receive_branch_transfer').length).toBe(1);
  expect(JSON.parse(calls.find(c => c.name === 'receive_branch_transfer').body)).toEqual({ p_transfer: 'tr5', p_items: ['c1'] });

  await page.click('[data-tab="send"]');
  await page.selectOption('#to-branch', 'b2');
  await page.selectOption('#scrap-karat', '18');
  await page.fill('#scrap-weight', '4.5'); await page.click('#scrap-add');
  await page.fill('#scrap-weight', '1.5'); await page.click('#scrap-add');
  await expect(page.locator('#scrap-list li')).toHaveCount(1); // same karat merged
  await page.fill('#cash-amount', '1200');
  await page.click('#send-btn');
  await expect(page.locator('#msg')).toContainText('TRF-000006');
  expect(JSON.parse(calls.find(c => c.name === 'send_branch_transfer').body)).toEqual({ p_from: STORE, p_to: 'b2', p_barcodes: null, p_notes: null,
    p_scrap: [{ karat: 18, weight: 6 }], p_cash: { amount: 1200, box: 'main' } });
});

test('single branch: nothing to transfer', async ({ page }) => {
  await install(page, { db: base(), rpc: { org_branches: () => ({ body: [branches[0]] }) } });
  await page.goto('/branch-transfers-ar.html');
  await expect(page.locator('#no-branches')).not.toHaveClass(/\bhidden\b/);
});
