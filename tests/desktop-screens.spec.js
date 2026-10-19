// Computer layouts without long empty boxes: main cash box, daily cash box, stock, traders, repairs board.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const now = Date.now(), ago = h => new Date(now - h * 36e5).toISOString();
const base = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
});
const desk = async page => page.setViewportSize({ width: 1440, height: 900 });

test('main cash box: numbers, one table, filter by type, summaries by currency and type', async ({ page }) => {
  const d = base();
  d.cash_movements = [
    { id: 'c1', store_id: STORE, box: 'main', direction: 'in', amount: 4200, currency: 'AED', description: 'تحصيل فاتورة بيع INV-1', invoice_id: 'i1', created_at: ago(0.2) },
    { id: 'c2', store_id: STORE, box: 'main', direction: 'out', amount: 60, currency: 'AED', description: 'مصروف قهوة', created_at: ago(0.1) },
    { id: 'c3', store_id: STORE, box: 'main', direction: 'in', amount: 100, currency: 'USD', description: 'دفعة من العميل أحمد', created_at: ago(0.05) },
  ];
  await install(page, { db: d });
  await desk(page);
  await page.goto('/main-cashbox-ar.html');
  await expect(page.locator('#mcTable tbody tr')).toHaveCount(3);
  await expect(page.locator('#mcKpis .mc-kpi')).toHaveCount(4);            // net, in, out + USD
  await page.locator('#mcTypes button', { hasText: 'مصروف' }).click();
  await expect(page.locator('#mcTable tbody tr')).toHaveCount(1);
  await expect(page.locator('#mcTable tbody')).toContainText('مصروف قهوة');
  await expect(page.locator('#mcByCur')).toContainText('USD');
  await expect(page.locator('#mcByType')).toContainText('بيع');
});

test('daily cash box: the add line sits above the table on the computer, the drawer count shows the difference', async ({ page }) => {
  const d = base();
  d.daily_cash_log = [{ id: 'e1', store_id: STORE, operation_type: 'بيع', direction: 'in', amount: 500, currency: 'AED', created_at: ago(0.1) }];
  await install(page, { db: d });
  await desk(page);
  await page.goto('/daily-cashbox-ar.html');
  await expect(page.locator('#gm-entries-col > #addForm.dc-inline')).toHaveCount(1);
  await expect(page.locator('#dcKpis')).toContainText('500.00');
  await page.fill('#dcc-AED', '480');
  await expect(page.locator('#dcd-AED')).toHaveText('نقص 20.00');
  await page.fill('#dcc-AED', '500');
  await expect(page.locator('#dcd-AED')).toHaveText('مطابق');
  await page.setViewportSize({ width: 390, height: 844 });                // phone: back under its button, folded
  await expect(page.locator('#dcAddToggle + #addForm')).toHaveClass(/\bhidden\b/);
});

test('stock on the computer: karat tiles, box share bars, recent pieces and what needs attention', async ({ page }) => {
  const d = base();
  d.pieces = [
    { id: 'p1', store_id: STORE, barcode: 'G1', karat: 21, weight_grams: 30, status: 'available', box_name: 'أساور', piece_type: 'أسوارة', photo_url: null, created_at: ago(2) },
    { id: 'p2', store_id: STORE, barcode: 'G2', karat: 18, weight_grams: 10, status: 'available', box_name: 'خواتم', piece_type: 'خاتم', photo_url: 'a.jpg', created_at: ago(1) },
  ];
  d.inventory_counts = []; d.gold_stock_lots = []; d.diamond_pieces = []; d.piece_barcode_history = [];
  await install(page, { db: d });
  await desk(page);
  await page.goto('/inventory-list-ar.html');
  await expect(page.locator('#inv-karat-tiles .gm-inv-mini')).toHaveCount(2);
  await expect(page.locator('#box-boxes .gm-row').first()).toHaveAttribute('style', /--share:75%/);  // أساور 30 of 40 g
  await expect(page.locator('#invRecent a').first()).toContainText('خاتم');                        // newest first
  await expect(page.locator('#invAttn')).toContainText('قطع بدون صورة');
  await expect(page.locator('#invLastCount')).toContainText('ما في جرد سابق');
});

test('traders on the computer: one table sorted by gold, the picked trader beside it', async ({ page }) => {
  const d = base();
  d.traders = [{ id: 't1', store_id: STORE, name: 'تاجر صغير', phone: '' }, { id: 't2', store_id: STORE, name: 'تاجر كبير', phone: '' }];
  d.trader_movements = [
    { id: 'm1', store_id: STORE, trader_id: 't1', movement_type: 'debt_increase', gold_24k_equivalent: 5, fab_fee_amount: 0, created_at: ago(5) },
    { id: 'm2', store_id: STORE, trader_id: 't2', movement_type: 'debt_increase', gold_24k_equivalent: 50, fab_fee_amount: 100, created_at: ago(3) },
  ];
  d.cash_movements = [];
  await install(page, { db: d });
  await desk(page);
  await page.goto('/ledger-ar.html');
  const rows = page.locator('#traders-list tbody tr');
  await expect(rows).toHaveCount(2);
  await expect(rows.first()).toContainText('تاجر كبير');
  await expect(page.locator('#ldSide')).toContainText('تاجر كبير');
  await rows.nth(1).click();
  await expect(page.locator('#ldSide')).toContainText('تاجر صغير');
  await expect(page.locator('#ldSide a[href*="cash-voucher-ar.html?party=trader&id=t1"]')).toHaveCount(2);
});

test('repairs board: a column per status, late tickets marked, the arrow moves a ticket on', async ({ page }) => {
  const d = base();
  d.repair_tickets = [
    { id: 'r1', store_id: STORE, ticket_number: 'R-1', customer_name: 'هلا', piece_description: 'خاتم', status: 'received', expected_ready_at: '2001-01-01', received_at: ago(30), created_at: ago(30) },
    { id: 'r2', store_id: STORE, ticket_number: 'R-2', customer_name: 'ريم', piece_description: 'سلسال', status: 'ready', received_at: ago(10), created_at: ago(10) },
  ];
  const calls = await install(page, { db: d });
  await desk(page);
  await page.goto('/repairs-ar.html');
  await expect(page.locator('#rpBoard .rp-col')).toHaveCount(4);
  await expect(page.locator('.rp-col[data-status="received"] .rp-card')).toContainText('متأخرة');
  await expect(page.locator('#rpLate')).toHaveText('متأخرة 1');
  await page.locator('.rp-col[data-status="received"] .rp-card button[aria-label^="نقل"]').click();
  await expect(page.locator('.rp-col[data-status="in_progress"] .rp-card')).toHaveCount(1);
  const patch = calls.find(c => c.method === 'PATCH' && c.name === 'repair_tickets');
  expect(JSON.parse(patch.body)).toEqual({ status: 'in_progress' });
});
