// Print page: "طباعة + شريحة جديدة" prints with a new chip number and cancels the old one.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const OLD = 'A1B2C3D4E5F6A7B8C9D0E1F2';

async function openPrint(page) {
  const calls = await install(page, { db: {
    stores: [{ id: STORE, name: 'محل', currency: 'AED', rfid_enabled: true }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    pieces: [{ id: 'p1', store_id: STORE, barcode: '000100', status: 'available', weight_grams: 10, karat: 18, rfid_epc: OLD }],
  }, rpc: { replace_piece_chip: (args) => ({ body: args.p_new_epc }) } });
  const printed = [];
  await page.goto('/piece-label-print-ar.html?id=p1');
  await page.waitForFunction(() => typeof currentPiece !== 'undefined' && currentPiece && currentPiece.barcode);
  await page.evaluate(() => {
    GMZebra.isAvailable = () => true;
    window.__printed = [];
    GMZebra.printAndEncodeRfid = async (o) => { window.__printed.push(o.epcHex); };
  });
  return { calls };
}

test('new-chip print writes a fresh chip, saves it and cancels the old one', async ({ page }) => {
  let asked = null;
  page.on('dialog', d => { if (asked === null) asked = d.message(); d.accept(); });
  const { calls } = await openPrint(page);
  await expect(page.locator('#rfid-new-btn')).not.toHaveClass(/\bhidden\b/);
  await page.click('#rfid-new-btn');
  await expect.poll(() => calls.some(c => c.name === 'replace_piece_chip')).toBe(true);
  const printed = await page.evaluate(() => window.__printed);
  const body = JSON.parse(calls.find(c => c.name === 'replace_piece_chip').body);
  expect(printed).toHaveLength(1);
  expect(body.p_old_epc).toBe(OLD);
  expect(body.p_new_epc).toBe(printed[0]);
  expect(body.p_new_epc).toMatch(/^[0-9A-F]{24}$/);
  expect(body.p_new_epc).not.toBe(OLD);
  expect(asked).toContain('000100');
  expect(asked).toContain('الباركود ما بيتغيّر');
});

test('normal RFID print keeps the stored chip number and does not cancel anything', async ({ page }) => {
  page.on('dialog', d => d.accept());
  const { calls } = await openPrint(page);
  await page.click('#rfid-btn');
  await expect.poll(() => page.evaluate(() => window.__printed.length)).toBe(1);
  expect(await page.evaluate(() => window.__printed[0])).toBe(OLD);
  expect(calls.some(c => c.name === 'replace_piece_chip')).toBe(false);
});
