// Daily backups page (بشار 2026-11-18): list the company's backups, open one, see what was deleted since,
// and bring one item back.
const { test, expect } = require('@playwright/test');
const zlib = require('zlib');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('backups: open a day, see the deleted trader movement, restore it', async ({ page }) => {
  await install(page, { db: {
    stores: [{ id: STORE }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'Owner' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    trader_movements: [{ id: 'm-keep', store_id: STORE, trader_id: 't1' }],
    customer_debts: [], cash_movements: [], expense_entries: [], customers: [], traders: [{ id: 't1', store_id: STORE, name: 'احمد الخياط - الشارقة' }],
  } });
  const snap = { store_id: STORE, tables: {
    traders: [{ id: 't1', store_id: STORE, name: 'احمد الخياط - الشارقة' }],
    trader_movements: [
      { id: 'm-keep', store_id: STORE, trader_id: 't1', source: 'cash_in', fab_fee_amount: 800, created_at: '2026-11-18T11:00:00Z' },
      { id: 'm-gone', store_id: STORE, trader_id: 't1', source: 'stock_given', weight_grams: 12.5, karat: 18, fab_fee_amount: 125, notes: 'سوارة', created_at: '2026-11-17T10:00:00Z' }],
    customer_debts: [], cash_movements: [], expense_entries: [], customers: [] } };
  const sent = [];
  await page.route(/\/functions\/v1\/daily-backup/, r => {
    const b = JSON.parse(r.request().postData()); sent.push(b);
    const body = b.action === 'list' ? { files: [{ name: '2026-11-17.json.gz', size: 900000 }] }
      : b.action === 'url' ? { url: 'https://backup.example.test/f.json.gz' } : { ok: true, rows: 1 };
    r.fulfill({ contentType: 'application/json', body: JSON.stringify(body) });
  });
  await page.route('https://backup.example.test/**', r => r.fulfill({ contentType: 'application/gzip', body: zlib.gzipSync(JSON.stringify(snap)) }));
  page.on('dialog', d => d.accept());
  await page.goto('/backups-ar.html');
  await page.click('text=17/11/2026');
  await expect(page.locator('#bk-rows')).toContainText('إخراج بضاعة');
  await expect(page.locator('#bk-rows')).toContainText('محذوف الآن');
  await expect(page.locator('#bk-rows')).not.toContainText('قبض كاش'); // still there → not listed by default
  await page.click('#bk-rows button:has-text("استرجاع")');
  await expect.poll(() => sent.find(b => b.action === 'restore')).toMatchObject({ table: 'trader_movements', id: 'm-gone', file: '2026-11-17.json.gz' });
});
