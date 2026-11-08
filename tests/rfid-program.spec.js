// Quick chip programming: scan a barcode, the label near the reader gets the piece's number.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const db = () => ({
  stores: [{ id: STORE, name: 'x', currency: 'USD', rfid_enabled: true }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  pieces: [
    { id: 'p1', store_id: STORE, barcode: '000805', description_ar: 'خاتم', karat: 18, weight_grams: 5, status: 'available' },
    { id: 'p2', store_id: STORE, barcode: '000806', description_ar: 'حلق', karat: 18, weight_grams: 3, status: 'available', rfid_epc: 'AAAA', rfid_encoded_at: '2026-11-01T10:00:00Z' },
    { id: 'p3', store_id: STORE, barcode: '000807', description_ar: 'سلسال', karat: 18, weight_grams: 4, status: 'sold' },
  ],
});
async function open(page, reader) {
  await page.addInitScript(r => { window.__w = []; window.__readerOK = r; }, reader);
  await install(page, { generic: true, db: db() });
  await page.goto('/rfid-program-ar.html');
  await page.evaluate(() => {
    GMUhf.available = async () => window.__readerOK; GMUhf.status = async () => ({ available: window.__readerOK, kind: 'zebra', name: 'RFD40' });
    GMUhf.readOne = async () => { throw new Error('blank'); }; GMUhf.writeEpc = async epc => { window.__w.push(epc); };
  });
  await expect(page.locator('#rpTotal')).toHaveText('2');
}

test('scan → written → counted, ready for the next one', async ({ page }) => {
  await open(page, true);
  await expect(page.locator('#rpDone')).toHaveText('1');
  await page.fill('#rpCode', '000805');
  await page.press('#rpCode', 'Enter');
  await expect(page.locator('#rpStatus')).toContainText('تمت البرمجة');
  const want = await page.evaluate(() => GMZebra.buildEpcHex('000805', GOLDMIND_STORE_ID));
  expect(await page.evaluate(() => window.__w)).toEqual([want]);
  await expect(page.locator('#rpDone')).toHaveText('2');
  await expect(page.locator('#rpCode')).toHaveValue('');
});

test('unknown or sold barcode is refused; no reader is explained', async ({ page }) => {
  await open(page, false);
  await page.fill('#rpCode', '000807');
  await page.press('#rpCode', 'Enter');
  await expect(page.locator('#rpStatus')).toContainText('غير موجود');
  await page.fill('#rpCode', '000805');
  await page.press('#rpCode', 'Enter');
  await expect(page.locator('#rpStatus')).toContainText('غير متصل');
  expect(await page.evaluate(() => window.__w.length)).toBe(0);
});

test('staff without «edit_piece»: nothing is written on the label', async ({ page }) => {
  await page.addInitScript(() => { window.__w = []; });
  await install(page, { generic: true, db: { ...db(), staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'staff', permissions: { view_inventory: true }, full_name: 'م' }] } });
  await page.goto('/rfid-program-ar.html');
  await page.evaluate(() => { GMUhf.available = async () => true; GMUhf.status = async () => ({ available: true }); GMUhf.readOne = async () => null; GMUhf.writeEpc = async e => { window.__w.push(e); }; });
  await expect(page.locator('#rpTotal')).toHaveText('2');
  await page.fill('#rpCode', '000805');
  await page.press('#rpCode', 'Enter');
  await expect(page.locator('#rpStatus')).toContainText('صلاحية');
  expect(await page.evaluate(() => window.__w.length)).toBe(0);
});
