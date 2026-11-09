// Period statement of the daily box: a card per day (opening, in, out, closing), rows under it,
// links shown across days (same colour + a chip to the partner), and linking two rows of different days.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const at = (d, h) => new Date(2026, 10, d, h, 0).toISOString();
const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  daily_cash_log: [
    { id: 'old', store_id: STORE, direction: 'in', amount: 1000, currency: 'USD', operation_type: 'رصيد سابق', created_at: at(1, 9) },
    { id: 'dep', store_id: STORE, direction: 'in', amount: 200, currency: 'USD', operation_type: 'عربون حسام', link_group: 'g1', created_at: at(6, 17) },
    { id: 'exp', store_id: STORE, direction: 'out', amount: 50, currency: 'USD', operation_type: 'ضيافة', created_at: at(6, 18) },
    { id: 'inv', store_id: STORE, direction: 'in', amount: 500, currency: 'USD', operation_type: 'فاتورة طقم', link_group: 'g1', created_at: at(7, 11) },
    { id: 'bank', store_id: STORE, direction: 'out', amount: 300, currency: 'USD', operation_type: 'إيداع بالبنك', created_at: at(7, 16) },
  ],
});

test('days as cards with running balances; a linked row points to its partner on another day', async ({ page }) => {
  await install(page, { db: db() });
  await page.goto('/daily-cashbox-range-ar.html?from=2026-11-06&to=2026-11-08');
  const days = page.locator('article.cr-day');
  await expect(days).toHaveCount(3);
  await expect(page.locator('#crSummary')).toContainText('1,000.00');      // opening = before the period
  await expect(page.locator('#crSummary')).toContainText('1,350.00');      // closing
  await expect(days.nth(0).locator('.cr-close')).toContainText('1,150.00');
  await expect(days.nth(1).locator('.cr-kv').first()).toContainText('1,150.00'); // next day opens where the last closed
  await expect(days.nth(2)).toContainText('يوم بلا حركات');
  // linked across days: same tint, and a chip naming the partner and its day
  const dep = page.locator('#r-dep'), inv = page.locator('#r-inv');
  await expect(dep).toHaveClass(/\blk\b/);
  expect(await dep.evaluate(e => e.style.getPropertyValue('--lk-ink'))).toBe(await inv.evaluate(e => e.style.getPropertyValue('--lk-ink')));
  await expect(dep.locator('.cr-chip')).toContainText('فاتورة طقم');
  await dep.locator('.cr-chip').click();
  await expect(inv).toHaveClass(/cr-focus/);
  // «المربوطة فقط»
  await page.locator('.cr-seg [data-f="linked"]').click();
  await expect(page.locator('#r-exp')).toBeHidden();
  await expect(inv).toBeVisible();
});

test('linking two rows of different days sets one link_group', async ({ page }) => {
  const calls = await install(page, { db: db() });
  await page.goto('/daily-cashbox-range-ar.html?from=2026-11-06&to=2026-11-07');
  await page.locator('#r-exp .cr-acts button[aria-label="ربط الحركة"]').click();
  await page.selectOption('#crLinkSel', 'bank');
  await page.locator('#crLinkModal button', { hasText: 'حفظ' }).click();
  await expect.poll(() => calls.filter(c => c.method === 'PATCH' && /daily_cash_log/.test(c.url)).length).toBe(2);
  const groups = calls.filter(c => c.method === 'PATCH' && /daily_cash_log/.test(c.url)).map(c => JSON.parse(c.body).link_group);
  expect(groups).toEqual(['lnk_exp', 'lnk_exp']);
});

test('a staff member without «عرض أيام الصندوق السابقة» cannot open the statement', async ({ page }) => {
  const d = db(); d.staff[0].role = 'staff'; d.staff[0].permissions = { manage_daily_cashbox: true };
  await install(page, { db: d });
  await page.goto('/daily-cashbox-range-ar.html?from=2026-11-06&to=2026-11-07');
  await expect(page.locator('#crNoAccess')).toBeVisible();
  await expect(page.locator('article.cr-day')).toHaveCount(0);
});
