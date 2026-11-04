// Trader vouchers: each movement shows its voucher number (opens a printable voucher);
// edit / delete / return only for the owner or staff with «edit_vouchers».
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const ago = d => new Date(Date.now() - d * 86400000).toISOString();
const db = (role, permissions) => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role, permissions, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  traders: [{ id: 't1', store_id: STORE, name: 'هادي', phone: '0933000000' }],
  pieces: [{ id: 'pc1', store_id: STORE, barcode: '000729', description_ar: 'إسوارة' }],
  trader_movements: [
    { id: 'm0', store_id: STORE, trader_id: 't1', movement_type: 'debt_increase', source: 'cash_in', fab_fee_amount: 100, gold_24k_equivalent: 0, voucher_no: 'REC-000001', created_at: ago(3) },
    { id: 'm1', store_id: STORE, trader_id: 't1', piece_id: 'pc1', movement_type: 'debt_decrease', source: 'stock_given', weight_grams: 20, accounting_weight_grams: 19.53, karat: 18, gold_24k_equivalent: 15, fab_fee_per_gram: 15, fab_fee_amount: 303, voucher_no: 'TOUT-000001', notes: 'إخراج بضاعة — باركود 000729 (إسوارة)', created_at: ago(2) },
  ],
});

test('owner: voucher number on the card, edit and return buttons shown', async ({ page }) => {
  await install(page, { generic: true, db: db('owner', {}) });
  await page.goto('/ledger-ar.html?trader=t1');
  const chip = page.locator('a[href*="trader-voucher-print-ar.html?no=TOUT-000001"]');
  await expect(chip).toBeVisible();
  await expect(page.locator('#trader-move-m1 button', { hasText: 'إرجاع للمخزن' })).toBeVisible();
  await expect(page.locator('#trader-move-m1 button', { hasText: 'حذف' })).toBeVisible();
});

test('staff without «edit_vouchers»: sees the voucher, no edit / delete / return', async ({ page }) => {
  await install(page, { generic: true, db: db('staff', { view_traders: true, edit_traders: true }) });
  await page.goto('/ledger-ar.html?trader=t1');
  await expect(page.locator('a[href*="TOUT-000001"]')).toBeVisible();
  await expect(page.locator('#trader-move-m1 button', { hasText: 'إرجاع للمخزن' })).toBeHidden();
  await expect(page.locator('#trader-move-m1 button', { hasText: 'تعديل' }).first()).toBeHidden();
  await expect(page.locator('#trader-move-m1 button', { hasText: 'حذف' })).toBeHidden();
});

test('voucher print: title, lines, totals and the trader balance after it', async ({ page }) => {
  await install(page, { generic: true, db: db('owner', {}) });
  await page.goto('/trader-voucher-print-ar.html?no=TOUT-000001');
  await expect(page.locator('#doc-title')).toHaveText('سند إخراج بضاعة للتاجر');
  await expect(page.locator('#v-number')).toHaveText('TOUT-000001');
  await expect(page.locator('#v-party')).toHaveText('هادي');
  await expect(page.locator('#lines')).toContainText('000729');
  await expect(page.locator('#t-money')).toHaveText('303.00 USD');
  // after: +15 g (given) and 303 − 100 = 203 cash, both owed to us
  await expect(page.locator('#b-gold')).toContainText('15.00 g لنا');
  await expect(page.locator('#b-cash')).toContainText('203.00 USD لنا');
});
