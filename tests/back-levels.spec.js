// Back button (بشار 2026-11-14): stepping piece to piece must not pile up in «back»; back from a
// trader's voucher returns to that trader, and back from the trader goes to the traders list.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const base = { stores: [{ id: STORE, name: 'محل', currency: 'USD' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] };
const P = id => ({ id, store_id: STORE, barcode: id, description_ar: 'خاتم', karat: 18, weight_grams: 5, status: 'available', box_name: 'قطع ذهبية', created_at: '2026-11-10T10:00:00Z' });

test('piece arrows: back returns to the stock list, not to the previous piece', async ({ page }) => {
  await install(page, { generic: true, db: { ...base, pieces: [P('a1'), P('a2'), P('a3')] } });
  await page.goto('/inventory-list-ar.html?box=' + encodeURIComponent('قطع ذهبية') + '&k=18');
  await page.evaluate(() => sessionStorage.setItem('gm_piece_nav', JSON.stringify(['a1', 'a2', 'a3'])));
  await page.goto('/piece-edit-ar.html?id=a1');
  await page.locator('#pcNext').click(); await page.waitForURL(/id=a2/);
  await page.locator('#pcNext').click(); await page.waitForURL(/id=a3/);
  await page.evaluate(() => gmSmartBack('index-ar.html'));
  await page.waitForURL(/inventory-list-ar\.html/);
  expect(page.url()).toContain('k=18');
  // and the stock page's own back steps up (pieces → karats → boxes) before leaving the page
  await page.waitForFunction(() => typeof gmInvBack === 'function' && !document.getElementById('piece-list-view').classList.contains('hidden'));
  for (let i = 0; i < 2 && /[?&](box|k)=/.test(page.url()); i++) await page.evaluate(() => gmInvBack());
  await expect(page).toHaveURL(/inventory-list-ar\.html$/); // still the stock page, now at the boxes
});

test('trader: back from a voucher reopens the trader; back again shows all traders', async ({ page }) => {
  await install(page, { generic: true, db: { ...base, traders: [{ id: 't1', store_id: STORE, name: 'هادي' }], trader_movements: [] } });
  await page.goto('/ledger-ar.html');
  await expect(page.locator('#traders-list-view')).toContainText('هادي');
  await page.evaluate(() => showTraderDetail('t1'));
  await expect(page).toHaveURL(/trader=t1&from=list/);
  await page.goto('/trader-voucher-print-ar.html?no=TOUT-1&store=' + STORE);
  await page.evaluate(() => gmSmartBack('ledger-ar.html'));
  await page.waitForURL(/ledger-ar\.html\?trader=t1/);
  await expect(page.locator('#trader-detail-view')).toBeVisible();
  await expect.poll(() => page.evaluate(() => currentTraderId)).toBe('t1');
  await page.evaluate(() => goBack());
  await expect(page.locator('#traders-list-view')).toBeVisible();
  await expect(page).not.toHaveURL(/trader=/);
});
