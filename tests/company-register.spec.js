const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

for (const [label, resp, check] of [
  ['emailed: password is not shown, the page says check your email', { success: true, email: 'a@b.co', emailed: true },
    async page => { await expect(page.locator('#success-note')).toContainText('أرسلنا كلمة المرور'); await expect(page.locator('#result-password-wrap')).toBeHidden(); }],
  ['no email service yet: the temporary password is shown', { success: true, email: 'a@b.co', temp_password: 'Xy7' },
    async page => { await expect(page.locator('#result-password')).toHaveText('Xy7'); }],
]) {
  test('company register — ' + label, async ({ page }) => {
    await install(page, { db: {} });
    await page.route(/functions\/v1\/register-company/, route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(resp) }));
    await page.goto('/company-register-ar.html');
    await page.fill('#f-company', 'محل تجربة'); await page.fill('#f-owner', 'سامر أحمد'); await page.fill('#f-email', 'a@b.co');
    await page.click('#submit-btn');
    await check(page);
  });
}

test('company register — a refused request shows the server message (rate limit)', async ({ page }) => {
  await install(page, { db: {} });
    await page.route(/functions\/v1\/register-company/, route => route.fulfill({ status: 429, contentType: 'application/json', body: JSON.stringify({ error: 'تم تجاوز عدد محاولات التسجيل المسموح.' }) }));
  await page.goto('/company-register-ar.html');
  await page.fill('#f-company', 'محل تجربة'); await page.fill('#f-owner', 'سامر أحمد'); await page.fill('#f-email', 'a@b.co');
  await page.click('#submit-btn');
  await expect(page.locator('#error-box')).toContainText('تجاوز');
});
