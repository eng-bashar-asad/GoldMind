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
