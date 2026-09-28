// list → invoice → edit → (save) → invoice → back must reach the list, not bounce to edit.
const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

test('back after editing an invoice goes to the list, no ping-pong', async ({ page }) => {
  await install(page, { generic: true });
  page.on('dialog', d => d.dismiss().catch(() => {}));
  const stack = () => page.evaluate(() => JSON.parse(sessionStorage.getItem('gm_nav_stack') || '[]'));
  await page.goto('/invoices-list-ar.html');
  await page.goto('/invoice-print-ar.html?id=inv1');
  await page.goto('/invoice-edit-ar.html?id=inv1');
  await page.goto('/invoice-print-ar.html?id=inv1'); // what saving does
  expect(await stack()).toEqual(['/invoices-list-ar.html', '/invoice-print-ar.html?id=inv1']);
  await page.evaluate(() => gmSmartBack('index-ar.html'));
  await expect(page).toHaveURL(/invoices-list-ar\.html$/);
});

test('back from the edit page (without saving) returns to the invoice', async ({ page }) => {
  await install(page, { generic: true });
  page.on('dialog', d => d.dismiss().catch(() => {}));
  await page.goto('/invoices-list-ar.html');
  await page.goto('/invoice-print-ar.html?id=inv1');
  await page.goto('/invoice-edit-ar.html?id=inv1');
  await page.evaluate(() => gmSmartBack('invoices-list-ar.html'));
  await expect(page).toHaveURL(/invoice-print-ar\.html\?id=inv1$/);
  await page.waitForFunction(() => typeof gmSmartBack === 'function');
  await page.evaluate(() => gmSmartBack('index-ar.html'));
  await expect(page).toHaveURL(/invoices-list-ar\.html$/);
});
