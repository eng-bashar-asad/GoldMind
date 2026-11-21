// Home: % change chips vs yesterday, 7-day sales bars with today lit, inventory-count ring; side-menu red badges.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const at = (dAgo, h, m = 0) => { const t = new Date(); t.setDate(t.getDate() - dAgo); t.setHours(h, m, 0, 0); return t.toISOString(); };
function db() {
  const now = new Date(), early = Math.max(0, now.getHours() - 1);
  return {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    invoices: [
      { id: 'a', store_id: STORE, type: 'sale', status: 'paid', total_amount: 3000, created_at: at(0, early) },
      { id: 'b', store_id: STORE, type: 'sale', status: 'unpaid', total_amount: 1000, created_at: at(1, early) },
      { id: 'c', store_id: STORE, type: 'sale', status: 'paid', total_amount: 9000, created_at: at(1, 23, 59) }, // later than now yesterday: not compared
      { id: 'd', store_id: STORE, type: 'sale', status: 'paid', total_amount: 2000, created_at: at(3, 12) },
    ],
    daily_cash_log: [{ id: 'l1', store_id: STORE, direction: 'in', amount: 10000, currency: 'AED', created_at: at(2, 12) }, { id: 'l2', store_id: STORE, direction: 'in', amount: 3000, currency: 'AED', created_at: at(0, early) }],
    inventory_counts: [{ id: 'k1', store_id: STORE, status: 'in_progress', expected_piece_count: 20, started_at: at(0, early), created_at: at(0, early) }],
    inventory_count_scans: Array.from({ length: 15 }, (_, i) => ({ id: 's' + i, count_id: 'k1', match_status: 'matched' })),
    repair_tickets: [{ id: 'r1', store_id: STORE, status: 'ready' }],
  };
}
for (const [name, vp] of [['computer', { width: 1440, height: 900 }]]) {
  test(`trends on ${name}`, async ({ page }) => {
    await page.setViewportSize(vp);
    await install(page, { generic: true, db: db() });
    await page.goto('/index-ar.html');
    const k = name === 'phone' ? 'M' : 'D';
    const bars = page.locator(`#gmWkBars${k} .gm-wk-col`);
    await expect(bars).toHaveCount(7);
    await expect(bars.last()).toHaveClass(/today/);
    await expect(bars.last()).toContainText('اليوم');
    const salesChip = page.locator(name === 'phone' ? '#todaySalesElDelta' : '#dskTodaySalesElDelta');
    await expect(salesChip).toContainText('200%'); // 3000 today vs 1000 by this time yesterday
    await expect(salesChip.locator('.gm-delta')).toHaveClass(/up/);
    await expect(page.locator(`#gmCnt${k}`)).toBeVisible();
    await expect(page.locator(`#gmCntRing${k}`)).toContainText('75%');
  });
}
test('phone home has no week bars, count ring or vs-yesterday chips', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await install(page, { generic: true, db: db() });
  await page.goto('/index-ar.html');
  await expect(page.locator('#dskTodaySalesElDelta')).toHaveCount(1, { timeout: 8000 }); // data has loaded
  await expect(page.locator('#gmWkRowM, #gmCntM, #todaySalesElDelta, #todayInvoiceCountElDelta, #dailyCashboxBalanceElDelta')).toHaveCount(0);
});
test('side menu shows red badges for repairs ready and unpaid invoices', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await install(page, { generic: true, db: db() });
  await page.goto('/invoices-list-ar.html');
  await expect(page.locator('#gmNav a.gn-a[href="repairs-ar.html"] .gn-badge.red')).toHaveCount(1, { timeout: 8000 });
  await expect(page.locator('#gmNav a.gn-a[href="invoices-list-ar.html"] .gn-badge.red')).toHaveCount(1);
});
