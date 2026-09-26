// Offline mode: reads come from the device, sales queue and post once when online.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  pieces: [
    { id: 'p1', store_id: STORE, barcode: 'B-001', karat: 18, weight_grams: 10, accounting_weight_grams: 10, status: 'available' },
    { id: 'p2', store_id: STORE, barcode: 'B-002', karat: 21, weight_grams: 5, accounting_weight_grams: 5, status: 'available' },
  ],
  customers: [
    { id: 'c1', store_id: STORE, name: 'أحمد خالد', phone: '0501111111' },
    { id: 'c2', store_id: STORE, name: 'سارة', phone: '0502222222' },
  ],
  gold_prices: [{ store_id: STORE, karat: 18, price_per_gram: 100 }, { store_id: STORE, karat: 21, price_per_gram: 117 }],
  diamond_pieces: [], gold_stock_lots: [],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
});

async function goOffline(page, context) {
  page.__gmNet.offline = true;
  await context.setOffline(true);
  await page.evaluate(() => window.dispatchEvent(new Event('offline')));
}

test.beforeEach(async ({ page }) => {
  page.on('pageerror', e => { throw e; });
});

test('lookups keep working with no internet', async ({ page, context }) => {
  await install(page, { db: db() });
  await page.goto('/tests/harness.html');
  await page.evaluate(async () => { await requireGoldMindSession(); await gmRefreshSnapshots(); });
  await goOffline(page, context);
  const res = await page.evaluate(async (S) => {
    const byBarcode = await goldmindClient.from('pieces').select('*').eq('store_id', S).eq('barcode', 'B-002').eq('status', 'available').maybeSingle();
    const missing = await goldmindClient.from('pieces').select('*').eq('store_id', S).eq('barcode', 'NOPE').eq('status', 'available').maybeSingle();
    const cust = await goldmindClient.from('customers').select('*').eq('store_id', S).or('name.ilike.%أحمد%,phone.ilike.%أحمد%').limit(8);
    const session = await requireGoldMindSession();
    return { piece: byBarcode.data && byBarcode.data.id, err: byBarcode.error, missing: missing.data, cust: cust.data.map(c => c.id), store: GOLDMIND_STORE_ID, signedIn: !!session };
  }, STORE);
  expect(res.err).toBeNull();
  expect(res.piece).toBe('p2');
  expect(res.missing).toBeNull();
  expect(res.cust).toEqual(['c1']);
  expect(res.signedIn).toBe(true);
  expect(res.store).toBe(STORE);
});

test('offline sale is queued, piece hidden, then posted exactly once', async ({ page, context }) => {
  const posted = [];
  await install(page, { db: db(), rpc: {
    post_sale_invoice: ({ p }) => {
      const dup = posted.find(x => x.client_ref === p.client_ref);
      if (!dup) posted.push(p);
      return { body: { id: 'inv-' + p.client_ref, invoice_number: 'INV-2026-000001', duplicate: !!dup } };
    } } });
  await page.goto('/tests/harness.html');
  await page.evaluate(async () => { await requireGoldMindSession(); await gmRefreshSnapshots(); });
  await goOffline(page, context);

  const r = await page.evaluate(async (S) => gmPostSale({ store_id: S, client_ref: 'ref-1', customer_id: 'c1', payment_method: 'cash',
    items: [{ mode: 'barcode', piece_id: 'p1', karat: 18, weight: 10, price: 1500 }] }, { customerName: 'أحمد' }), STORE);
  expect(r).toEqual({ queued: true });
  const after = await page.evaluate(async (S) => {
    const { data } = await goldmindClient.from('pieces').select('*').eq('store_id', S).eq('barcode', 'B-001').eq('status', 'available').maybeSingle();
    return { stillThere: !!data, queue: gmQueue().length, badge: document.getElementById('gm-offline-badge')?.textContent };
  }, STORE);
  expect(after.stillThere).toBe(false);
  expect(after.queue).toBe(1);
  expect(after.badge).toContain('1 فاتورة بانتظار الترحيل');
  expect(posted).toHaveLength(0);

  page.__gmNet.offline = false;
  await context.setOffline(false);
  await page.evaluate(async () => { window.dispatchEvent(new Event('online')); await new Promise(r => setTimeout(r, 300)); await gmSyncQueue(); await gmSyncQueue(); });
  expect(posted).toHaveLength(1);
  expect(posted[0].items[0].piece_id).toBe('p1');
  expect(await page.evaluate(() => gmQueue().length)).toBe(0);
});

test('a sale the server refuses stays on the device with the reason', async ({ page, context }) => {
  await install(page, { db: db(), rpc: {
    post_sale_invoice: () => ({ status: 400, body: { code: 'P0001', message: 'القطعة B-001 مو متاحة للبيع (حالتها: sold)' } }) } });
  await page.goto('/tests/harness.html');
  await page.evaluate(async () => { await requireGoldMindSession(); await gmRefreshSnapshots(); });
  await goOffline(page, context);
  await page.evaluate(async (S) => gmPostSale({ store_id: S, client_ref: 'ref-2', customer_id: 'c1', payment_method: 'cash',
    items: [{ piece_id: 'p1', karat: 18, weight: 10, price: 1500 }] }, {}), STORE);
  page.__gmNet.offline = false;
  await context.setOffline(false);
  const q = await page.evaluate(async () => { window.dispatchEvent(new Event('online')); await new Promise(r => setTimeout(r, 300)); await gmSyncQueue(); return gmQueue(); });
  expect(q).toHaveLength(1);
  expect(q[0].status).toBe('failed');
  expect(q[0].error).toContain('مو متاحة');
});

test('offline sale far below gold value asks first', async ({ page, context }) => {
  await install(page, { db: db() });
  await page.goto('/tests/harness.html');
  await page.evaluate(async () => { await requireGoldMindSession(); await gmRefreshSnapshots(); });
  await goOffline(page, context);
  let asked = '';
  page.on('dialog', d => { asked = d.message(); d.dismiss(); });
  const r = await page.evaluate(async (S) => gmPostSale({ store_id: S, client_ref: 'ref-3', customer_id: 'c1', payment_method: 'cash',
    items: [{ piece_id: 'p1', karat: 18, weight: 10, price: 50 }] }, {}), STORE); // gold value ~1000
  expect(asked).toContain('أقل من نص قيمة الذهب');
  expect(r.error).toBeTruthy();
  expect(await page.evaluate(() => gmQueue().length)).toBe(0);
});

test('online low-price answer from the server asks, then resends confirmed', async ({ page }) => {
  const seen = [];
  await install(page, { db: db(), rpc: { post_sale_invoice: ({ p }) => {
    seen.push(!!p.confirm_low_price);
    return p.confirm_low_price ? { body: { id: 'i1', invoice_number: 'INV-1' } } : { status: 400, body: { code: 'P0001', message: 'LOW_PRICE:\n• B-001: 50' } };
  } } });
  await page.goto('/tests/harness.html');
  page.on('dialog', d => d.accept());
  const r = await page.evaluate(async (S) => { await requireGoldMindSession(); return gmPostSale({ store_id: S, client_ref: 'ref-4', customer_id: 'c1', payment_method: 'cash',
    items: [{ piece_id: 'p1', karat: 18, weight: 10, price: 50 }] }, {}); }, STORE);
  expect(r.invoice_number).toBe('INV-1');
  expect(seen).toEqual([false, true]);
});

test('a sale saved while an older one is still syncing is not lost', async ({ page, context }) => {
  const posted = [];
  await install(page, { db: db(), rpc: { post_sale_invoice: async ({ p }) => {
    await new Promise(r => setTimeout(r, 800)); posted.push(p.client_ref);
    return { body: { id: 'i-' + p.client_ref, invoice_number: 'N' } }; } } });
  await page.goto('/tests/harness.html');
  await page.evaluate(async () => { await requireGoldMindSession(); await gmRefreshSnapshots(); });
  await goOffline(page, context);
  await page.evaluate((S) => gmPostSale({ store_id: S, client_ref: 'A', customer_id: 'c1', payment_method: 'cash', items: [{ piece_id: 'p1', karat: 18, weight: 10, price: 1500 }] }, {}), STORE);
  page.__gmNet.offline = false; await context.setOffline(false);
  await page.waitForFunction(() => navigator.onLine);
  await page.evaluate(() => { window.__sync = gmSyncQueue(); });           // A is being posted (slow)
  await page.waitForTimeout(200);
  page.__gmNet.offline = true; await context.setOffline(true);
  await page.evaluate((S) => gmPostSale({ store_id: S, client_ref: 'B', customer_id: 'c1', payment_method: 'cash', items: [{ piece_id: 'p2', karat: 21, weight: 5, price: 900 }] }, {}), STORE);
  await page.evaluate(() => window.__sync);
  await expect.poll(() => posted.length).toBe(1);                         // the (auto or manual) sync of A finished
  await page.waitForFunction(() => !gmSyncing);
  const q = await page.evaluate(() => gmQueue().map(x => x.payload.client_ref + ':' + x.status));
  expect(posted).toEqual(['A']);
  expect(q).toEqual(['B:pending']);
});
