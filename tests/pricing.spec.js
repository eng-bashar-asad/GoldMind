// Pricing: yearly + quarterly installments, AED/USD switch, e-invoicing quota.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const PLANS = [
  { id: 'b', key: 'basic', name_ar: 'الأساسية', highlights_ar: ['حسابات الزبائن والتجار'], sort_order: 1, is_active: true, is_custom: false, included_staff: 4, einvoice_monthly_quota: null, features: { profit_report: true, einvoice: false },
    prices: { AED: { yearly: 4490, quarterly: 1235, extra_staff_yearly: 549, einvoice_addon_monthly: 99, einvoice_overage: 1 }, USD: { yearly: 1225, quarterly: 337, extra_staff_yearly: 150, einvoice_addon_monthly: 27, einvoice_overage: 0.27 } } },
  { id: 'p', key: 'pro', name_ar: 'الاحترافية', sort_order: 2, is_active: true, is_custom: false, included_staff: 8, einvoice_monthly_quota: 300, features: { profit_report: true, einvoice: true },
    prices: { AED: { yearly: 7990, quarterly: 2199, extra_staff_yearly: 479, einvoice_overage: 1 }, USD: { yearly: 2175, quarterly: 599, extra_staff_yearly: 130, einvoice_overage: 0.27 } } },
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
  await expect(list).toContainText('$1,225'); // dollars by default, even for a dirham store
  await expect(list).toContainText('حسابات الزبائن والتجار');
  await expect(list).toContainText('$599 كل 3 أشهر');
  await expect(list).toContainText('حتى 300 فاتورة شهرياً');
  await expect(page.locator('#staff-usage-note')).toContainText('$150 سنوياً');
  await page.click('.cur-btn[data-cur="AED"]');
  await expect(list).toContainText('4,490 AED');
  await expect(page.locator('#staff-usage-note')).toContainText('549 AED سنوياً لكل موظف');
  if (process.env.UI_OUT) await page.screenshot({ path: `${process.env.UI_OUT}/subscription.png`, fullPage: true });
});

test('landing page shows prices and remembers the currency', async ({ page }) => {
  await install(page, {});
  await page.goto('/landing-ar.html');
  await expect(page.locator('#lp-plans')).toContainText('$6,600');
  await expect(page.locator('#lp-plans')).toContainText('سعر خاص — تواصل معنا');
  await expect(page.locator('#lp-plans')).toContainText('مسدس الجرد');
  await page.click('.lp-cur[data-cur="AED"]');
  await expect(page.locator('#lp-plans')).toContainText('24,240 درهم');
  if (process.env.UI_OUT) await page.locator('#pricing-h').scrollIntoViewIfNeeded(), await page.screenshot({ path: `${process.env.UI_OUT}/landing-pricing.png` });
  await page.reload();
  await expect(page.locator('#lp-plans')).toContainText('15,425 درهم'); // remembered
  await page.click('.lp-cur[data-cur="USD"]');
  await expect(page.locator('#lp-plans')).toContainText('$4,200');
  await expect(page.locator('#lp-plans')).toContainText('6 مستخدمين ضمن الباقة');
});
