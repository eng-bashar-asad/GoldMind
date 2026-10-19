// Computer layout: fixed side menu, small bar on narrow laptops, inventory as a table, sale screen columns.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
});

test('computer: the menu stays open beside the page; phone: it is a drawer', async ({ page }) => {
  await install(page, { db: db() });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/customers-ar.html');
  await expect(page.locator('html')).toHaveClass(/\bgm-desk\b/);
  await expect(page.locator('html')).not.toHaveClass(/\bgm-mini\b/);
  await page.setViewportSize({ width: 1100, height: 800 });
  await expect(page.locator('html')).toHaveClass(/\bgm-mini\b/); // small bar under 1280px
  await page.click('#gmNav .gn-mini');                          // the toggle is remembered
  await page.setViewportSize({ width: 1440, height: 900 });
  await expect(page.locator('html')).not.toHaveClass(/\bgm-mini\b/);
});

test('inventory pieces: a table on the computer, cards on the phone', async ({ page }) => {
  await install(page, { db: db() });
  const piece = { id: 'p1', barcode: '000120', karat: 21, weight_grams: 5, accounting_weight_grams: 4.8, status: 'available', box_name: 'قطع ذهبية', piece_type: 'خاتم' };
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/inventory-list-ar.html');
  const wide = await page.evaluate(p => piecesHtml([p]), piece);
  expect(wide).toContain('<table');
  expect(wide).toContain('000120');
  await page.setViewportSize({ width: 390, height: 844 });
  const narrow = await page.evaluate(p => piecesHtml([p]), piece);
  expect(narrow).toContain('gm-piece');
  expect(await page.evaluate(() => piecesHtml([]))).toBe('');
});

test('sale screen: items table under the entry boxes on the computer, back in place on the phone', async ({ page }) => {
  await install(page, { db: db() });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/new-sale-ar.html');
  await expect(page.locator('#ns-main > #ns-cart')).toHaveCount(1);
  await expect(page.locator('#ns-side > #ns-customer')).toHaveCount(1);
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.locator('#ns-main > #ns-customer')).toHaveCount(1);
  await expect(page.locator('#ns-side > #ns-cart')).toHaveCount(1);
});

test('piece page on the computer: compact specs, suggested price, transfer link, log as a table', async ({ page }) => {
  const d = db();
  d.gold_prices = [{ store_id: STORE, karat: 21, price_per_gram: 300 }];
  d.pieces = [{ id: 'p1', store_id: STORE, barcode: '000120', karat: 21, weight_grams: 5.4, accounting_weight_grams: 5, cost_fabrication_per_gram: 10, color: 'Gold', status: 'available', piece_type: 'خاتم', box_name: 'قطع ذهبية' }];
  d.piece_movements = [{ id: 'm1', store_id: STORE, piece_id: 'p1', event_type: 'created', note: 'إدخال', created_at: '2026-10-10T10:00:00Z' }];
  d.piece_classification_options = []; d.zebra_label_fields = [];
  await install(page, { db: d });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/piece-edit-ar.html?id=p1');
  await expect(page.locator('#pcAcc')).toHaveText('5.00 غ');
  await expect(page.locator('#pcBranch')).toHaveText('محل');
  await expect(page.locator('#pcSuggest')).toHaveText('1,550.00');          // 5 × 300 + 5 × 10
  await expect(page.locator('#pcStones')).toHaveClass(/\bhidden\b/);        // no stones → no card
  await expect(page.locator('#pcMoveBtn')).toHaveAttribute('href', 'branch-transfers-ar.html?barcode=000120');
  await expect(page.locator('#piece-log-list table.pc-log tbody tr')).toHaveCount(1);
});

test('home on the computer: today\'s movements as a table coloured by kind; glossy quick actions', async ({ page }) => {
  const d = db();
  const now = new Date().toISOString();
  d.invoices = [{ id: 'i1', store_id: STORE, invoice_number: 'INV-1', type: 'sale', status: 'paid', total_amount: 500, created_at: now, customer: { name: 'رامي' } }];
  d.cash_movements = [{ id: 'm1', store_id: STORE, direction: 'in', amount: 500, description: 'مبيعات', invoice_id: 'i1', created_at: now },
    { id: 'm2', store_id: STORE, direction: 'in', amount: 80, description: 'دفعة من العميل', created_at: now }];
  await install(page, { db: d, generic: true });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/index-ar.html');
  const rows = page.locator('#dskMovesTable tbody tr');
  await expect(rows).toHaveCount(2);
  await expect(page.locator('#dskMovesTable tr[data-href="invoice-print-ar.html?id=i1"]')).toContainText('رامي');
  await expect(page.locator('#dskMovesTable tr[data-href="invoice-print-ar.html?id=i1"] .t')).toHaveText('بيع');
  await expect(rows.filter({ hasText: 'دفعة من العميل' }).locator('.t')).toHaveText('دفعة زبون');
  await expect(page.locator('#dskActionStrip .gm-gi').first()).toBeVisible();
  await expect(page.locator('#mobActionStrip .gm-gi').last()).toBeAttached(); // the «تخصيص» tile
});

test('phone home: the page has no white strips (the small-menu class on <html> must not pick up card styles)', async ({ page }) => {
  await install(page, { db: db(), generic: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/index-ar.html');
  await expect(page.locator('html')).toHaveClass(/\bgm-mini\b/);
  expect(await page.evaluate(() => getComputedStyle(document.documentElement).paddingLeft)).toBe('0px');
});

test('phone home: press and hold an icon, drag it onto another, the new order is kept', async ({ page }) => {
  await install(page, { db: db(), generic: true, realCdn: true }); // real CSS: the icons sit in a 4-column grid
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/index-ar.html');
  const tiles = page.locator('#mobActionStrip .gm-qg[data-id]');
  await expect(tiles.first()).toBeVisible();
  await page.waitForTimeout(2000); // the strip is drawn again once the staff permissions are in
  await tiles.first().scrollIntoViewIfNeeded();
  await page.waitForTimeout(300);
  const before = await tiles.evaluateAll(t => t.map(x => x.dataset.id));
  const a = await tiles.nth(0).boundingBox(), b = await tiles.nth(2).boundingBox();
  await page.mouse.move(a.x + a.width / 2, a.y + 20);
  await page.mouse.down();
  await page.waitForTimeout(600);                                          // hold
  await page.mouse.move(b.x + b.width / 2, b.y + 20, { steps: 8 });
  await page.mouse.up();
  const after = await tiles.evaluateAll(t => t.map(x => x.dataset.id));
  expect(after).toEqual([before[1], before[2], before[0], ...before.slice(3)]);
  await expect(page.locator('#mobActionStrip')).toHaveClass(/\bgm-arrange\b/);
  const saved = await page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('goldmind_mobile_quick_actions_v4_')).map(k => JSON.parse(localStorage[k]))[0]);
  expect(saved.slice(0, 3)).toEqual(after.slice(0, 3));
  // in arrange mode a tap does not leave the page; «تم الترتيب» ends it
  await tiles.nth(1).click({ force: true }); // the icons wiggle while arranging
  await expect(page).toHaveURL(/index-ar\.html/);
  await page.click('#mobArrangeDone');
  await expect(page.locator('#mobActionStrip')).not.toHaveClass(/\bgm-arrange\b/);
});

test('alert() shows a notification that does not block, and it carries over to the next page', async ({ page }) => {
  await install(page, { db: db(), generic: true });
  await page.goto('/customers-ar.html');
  await page.waitForFunction(() => !!window.gmNotify);
  await page.evaluate(() => alert('تعذّر الحفظ: تجربة'));
  await expect(page.locator('#gmToasts .gm-toast.err')).toContainText('تعذّر الحفظ');
  await page.evaluate(() => alert('تم الحفظ'));
  await expect(page.locator('#gmToasts .gm-toast.ok')).toContainText('تم الحفظ');
  await page.goto('/invoices-list-ar.html');
  await expect(page.locator('#gmToasts')).toContainText('تعذّر الحفظ');
});

test('an empty list gets the small drawing', async ({ page }) => {
  await install(page, { db: db() });
  await page.goto('/customers-ar.html');
  await page.evaluate(() => { const p = document.createElement('p'); p.className = 'text-center py-8'; p.textContent = 'لا يوجد زبائن مطابقون.'; p.id = 'emp'; document.body.appendChild(p); });
  await expect(page.locator('#emp')).toHaveClass(/\bgm-empty\b/);
});

test('«تخصيص»: each icon can get its own colour, kept for this staff member', async ({ page }) => {
  await install(page, { db: db(), generic: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/index-ar.html');
  await page.waitForTimeout(1500);
  await page.evaluate(() => document.getElementById('mobCustomizeBtn').click());
  const row = page.locator('#mobColorRows .gm-qc-row[data-id="cashbox"]');
  await row.locator('.gm-qc-pick').click();                                  // opens the colour dots
  await row.locator('button[data-c="#8E5BD9"]').click();
  await expect(row.locator('button[data-c="#8E5BD9"]')).toHaveAttribute('aria-checked', 'true');
  expect(await page.locator('#mobActionStrip .gm-qg[data-id="cashbox"] .gm-gi').getAttribute('style')).toContain('#8E5BD9');
  await page.reload(); await page.waitForTimeout(1500);
  expect(await page.locator('#mobActionStrip .gm-qg[data-id="cashbox"] .gm-gi').getAttribute('style')).toContain('#8E5BD9');
  await page.setViewportSize({ width: 1440, height: 900 });                 // same colour on the computer
  expect(await page.locator('#dskActionStrip a[href="daily-cashbox-ar.html"] .gm-gi').getAttribute('style')).toContain('#8E5BD9');
});
