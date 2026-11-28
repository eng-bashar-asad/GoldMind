// In-app support assistant (gm-assistant.js + the `assistant` Edge Function's knowledge file).
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const { build, OUT } = require('../supabase/functions/assistant/build-knowledge');

const DB = {
  stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
};

test('knowledge.json matches the guides and pages (run build-knowledge.js after changing them)', () => {
  expect(JSON.parse(fs.readFileSync(OUT, 'utf8'))).toEqual(build());
});

test('assistant: opens, sends the conversation with the company id, shows the reply safely', async ({ page }) => {
  await install(page, { db: DB });
  const sent = [];
  await page.route(/\/functions\/v1\/assistant/, async (r) => {
    sent.push(JSON.parse(r.request().postData()));
    await r.fulfill({ json: { reply: 'افتح [الفواتير](invoices-list-ar.html) ثم **بحث**. <img src=x onerror="window.__xss=1"> [سيئ](javascript:alert(1))' } });
  });
  await page.goto('/reports-ar.html');
  const btn = page.locator('#gmAssistantBtn');
  await expect(btn).toBeVisible();
  // closed panel must not count as an open dialog (that pauses the phone gestures in gm-nav.js)
  expect(await page.locator('[role="dialog"]:not(.hidden)').count()).toBe(0);
  await btn.click();
  await page.locator('#gmaInput').fill('وين الفواتير؟');
  await page.locator('#gmaSend').click();
  const reply = page.locator('#gmaList .gma-a').last();
  await expect(reply).toContainText('بحث');
  await expect(reply.locator('a[href="invoices-list-ar.html"]')).toHaveText('الفواتير');
  expect(await reply.locator('img, a[href^="javascript"]').count()).toBe(0); // escaped, only app pages become links
  expect(await page.evaluate(() => window.__xss)).toBeUndefined();
  expect(sent[0]).toMatchObject({ store_id: STORE, page: 'reports-ar.html', messages: [{ role: 'user', content: 'وين الفواتير؟' }] });
});

test('assistant: server error is shown and the question stays in the box', async ({ page }) => {
  await install(page, { db: DB });
  await page.route(/\/functions\/v1\/assistant/, (r) => r.fulfill({ status: 503, json: { error: 'المساعد غير مفعّل بعد.' } }));
  await page.goto('/reports-ar.html');
  await page.locator('#gmAssistantBtn').click();
  await page.locator('#gmaInput').fill('سؤال');
  await page.locator('#gmaSend').click();
  await expect(page.locator('#gmaList .gma-err')).toHaveText('المساعد غير مفعّل بعد.');
  await expect(page.locator('#gmaInput')).toHaveValue('سؤال');
  expect(await page.locator('#gmaList .gma-u').count()).toBe(0);
});

test('assistant: not loaded on print pages', async ({ page }) => {
  await install(page, { db: DB });
  await page.goto('/invoice-print-ar.html');
  await page.waitForTimeout(800);
  expect(await page.locator('#gmAssistantBtn').count()).toBe(0);
});
