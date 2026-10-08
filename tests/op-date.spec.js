// Back-dated movements: the date field in a movement form sends x-gm-op-date; today sends nothing.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

test('trader discount can be back-dated, other forms are not', async ({ page }) => {
  await install(page, { generic: true, rpc: { trader_discount: () => ({ body: 'x' }) }, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    traders: [{ id: 't1', store_id: STORE, name: 'جليل' }],
    trader_movements: []
  } });
  const sent = [];
  page.on('request', r => { if (r.url().includes('/rpc/trader_discount')) sent.push(r.headers()['x-gm-op-date'] || null); });
  page.on('dialog', d => d.accept());
  await page.goto('/ledger-ar.html?trader=t1');
  await page.click('button:has-text("خصم على الحساب النقدي")');
  const date = page.locator('#trader-discount-form .gm-opdate input');
  await expect(date).toBeVisible();
  // today -> no header
  await page.fill('#td-amount', '5');
  await page.click('#td-btn');
  await expect.poll(() => sent.length).toBe(1);
  expect(sent[0]).toBeNull();
  // past date -> header
  await page.click('button:has-text("خصم على الحساب النقدي")');
  await date.fill('2026-09-15');
  await date.dispatchEvent('change');
  await expect(page.locator('#trader-discount-form .gm-opdate-note')).toContainText('بتاريخ سابق');
  await page.fill('#td-amount', '7');
  await page.click('#td-btn');
  await expect.poll(() => sent.length).toBe(2);
  expect(sent[1]).toBe('2026-09-15');
  // a click in an undated form clears it
  await page.evaluate(() => { const f = document.getElementById('trader-opening-balance-form'); f.classList.remove('hidden'); f.querySelector('input,button').click(); });
  expect(await page.evaluate(() => window.gmOpDate)).toBeNull();
});

test('customer and cash-voucher forms show the date field', async ({ page }) => {
  await install(page, { generic: true, db: {
    stores: [{ id: STORE, name: 'x', currency: 'USD' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    customers: [{ id: 'c1', store_id: STORE, name: 'ديمة' }]
  } });
  for (const [url, ids] of [['/customer-debts-ar.html?open=c1', ['settle-form', 'cashout-form', 'discount-form']], ['/cash-voucher-ar.html', ['cv-form']]]) {
    await page.goto(url);
    for (const id of ids) await expect(page.locator(`#${id} .gm-opdate input[type=date]`)).toHaveCount(1);
  }
});
