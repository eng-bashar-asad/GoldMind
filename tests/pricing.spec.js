// Pricing: yearly only (no quarterly), dollars only, e-invoicing quota, 14-day refund policy.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const PLANS = [
  { id: 'b', key: 'basic', name_ar: 'الأساسية', highlights_ar: ['حسابات الزبائن والتجار'], sort_order: 1, is_active: true, is_custom: false, included_staff: 4, einvoice_monthly_quota: null, features: { profit_report: true, einvoice: false },
    prices: { AED: { yearly: 4490, extra_staff_yearly: 549, einvoice_addon_monthly: 99, einvoice_overage: 1 }, USD: { yearly: 1225, extra_staff_yearly: 150, einvoice_addon_monthly: 27, einvoice_overage: 0.27 } } },
  { id: 'p', key: 'pro', name_ar: 'الاحترافية', sort_order: 2, is_active: true, is_custom: false, included_staff: 8, einvoice_monthly_quota: 300, features: { profit_report: true, einvoice: true },
    prices: { AED: { yearly: 7990, extra_staff_yearly: 479, einvoice_overage: 1 }, USD: { yearly: 2175, extra_staff_yearly: 130, einvoice_overage: 0.27 } } },
];

test('subscription page: store currency by default, switch to dollars', async ({ page }) => {
  await install(page, {
    db: {
      stores: [{ id: STORE, currency: 'AED', organization_id: null, name: 'محل' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      platform_admins: [],
      plans: PLANS,
      subscriptions: [{ id: 's', store_id: STORE, plan_id: 'b', status: 'active', current_period_end: '2027-01-01', plans: PLANS[0] }],
    },
    rpc: { check_staff_limit: () => ({ body: [{ current_count: 5, included_count: 4, extra_price: 150 }] }) },
  });
  await page.goto('/subscription-ar.html');
  const list = page.locator('#plans-list');
  await expect(list).toContainText('$1,225'); // always dollars, even for a dirham store
  await expect(list).toContainText('حسابات الزبائن والتجار');
  await expect(list).not.toContainText('كل 3 أشهر');
  await expect(page.locator('#refund-policy')).toContainText('14 يوماً');
  await expect(list).toContainText('حتى 300 فاتورة شهرياً');
  await expect(page.locator('#staff-usage-note')).toContainText('$150 سنوياً');
  await expect(page.locator('.cur-btn')).toHaveCount(0);
  await expect(list).not.toContainText('AED');
  await expect(list).toContainText('بالدرهم في الإمارات مثلاً');
  if (process.env.UI_OUT) await page.screenshot({ path: `${process.env.UI_OUT}/subscription.png`, fullPage: true });
});

test('landing page shows the plans in dollars', async ({ page }) => {
  await install(page, {});
  await page.goto('/landing-ar.html');
  const p = page.locator('#lp-plans');
  await expect(p).toContainText('$5,990');
  await expect(p).toContainText('$8,390');
  await expect(p).toContainText('سعر خاص — تواصل معنا');
  await expect(p).toContainText('مسدس الجرد');
  await expect(p).toContainText('6 مستخدمين ضمن الباقة');
  await expect(p).toContainText('ما يعادلها بعملة بلدك');
  await expect(p).not.toContainText('كل 3 أشهر');
  if (process.env.UI_OUT) await page.locator('#pricing-h').scrollIntoViewIfNeeded(), await page.screenshot({ path: `${process.env.UI_OUT}/landing-pricing.png` });
});

test('terms page states yearly-only and the 14-day refund window', async ({ page }) => {
  await install(page, {});
  await page.goto('/terms-ar.html');
  await expect(page.locator('body')).toContainText('الاشتراك سنوي فقط');
  await expect(page.locator('body')).toContainText('خلال 14 يوماً من تاريخ الاشتراك');
});

// Multi-branch 3.3: each branch's yearly price, what a new branch owes until the company renewal,
// one renewal date and total; GoldMind (platform admin) records the payments.
test('subscription page: branch billing with prorated due and one company renewal', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const calls = await install(page, {
    db: {
      stores: [{ id: STORE, currency: 'USD', organization_id: 'o1', name: 'محل' }],
      staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
      user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
      plans: PLANS,
      subscriptions: [{ id: 's', store_id: STORE, plan_id: 'b', status: 'active', current_period_end: '2027-04-30', plans: PLANS[0] }],
    },
    rpc: {
      check_staff_limit: () => ({ body: [{ current_count: 2, included_count: 4, extra_price: 150 }] }),
      is_platform_admin: () => ({ body: true }),
      branch_billing: () => ({ body: [
        { store_id: STORE, store_name: 'المول', is_head: true, plan_name: 'الأساسية', status: 'active', period_end: '2027-04-30T00:00:00Z', yearly: 5990, currency: 'USD', branch_due: null, branch_due_currency: null },
        { store_id: 'b2', store_name: 'فرع الحمرا', is_head: false, plan_name: 'الأساسية', status: 'active', period_end: '2027-04-30T00:00:00Z', yearly: 5990, currency: 'USD', branch_due: 2970.38, branch_due_currency: 'USD' }] }),
      record_branch_payment: () => ({ body: null }),
      record_org_renewal: () => ({ body: '2028-04-30T00:00:00Z' }),
    },
  });
  await page.goto('/subscription-ar.html');
  const sec = page.locator('#branch-billing');
  await expect(sec).not.toHaveClass(/\bhidden\b/);
  await expect(sec).toContainText('فرع الحمرا');
  await expect(sec).toContainText('2,970.38');
  await expect(page.locator('#bb-total')).toContainText('11,980');
  await sec.locator('[data-pay="b2"]').click();
  await expect.poll(() => calls.some(c => c.name === 'record_branch_payment')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'record_branch_payment').body).p_store).toBe('b2');
  await page.click('#bb-renew');
  await expect.poll(() => calls.some(c => c.name === 'record_org_renewal')).toBe(true);
  expect(JSON.parse(calls.find(c => c.name === 'record_org_renewal').body)).toMatchObject({ p_store: STORE, p_months: 12 });
});
