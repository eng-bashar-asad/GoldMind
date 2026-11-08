// Computer: the Zebra sled over a COM port (Web Serial + ZETI text commands).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const DB = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'AED', rfid_enabled: true }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  pieces: [{ id: 'p1', store_id: STORE, barcode: '000123', status: 'available', karat: 18, weight_grams: 5 }],
});
// A fake RFD40 on a serial port: one label in front of it; only the "wr -mb epc -os 2 -d" spelling writes.
function fakeZebra(tags) {
  return ({ tags }) => {
    const enc = new TextEncoder(), dec = new TextDecoder();
    let ctl, inv = null;
    const out = s => ctl && ctl.enqueue(enc.encode(s + '\r\n'));
    window.__zeti = { tags, cmds: [] };
    const port = {
      getInfo: () => ({ bluetoothServiceClassId: '00001101-0000-1000-8000-00805f9b34fb' }),
      open: async () => {},
      close: async () => {},
      readable: new ReadableStream({ start(c) { ctl = c; } }),
      writable: new WritableStream({ write(chunk) {
        const c = dec.decode(chunk).trim(); window.__zeti.cmds.push(c);
        out('Command:' + c);
        if (c === 'in') { inv = setInterval(() => window.__zeti.tags.forEach(t => out(t + ',RSSI:-40')), 100); return; }
        if (c === 'a') { clearInterval(inv); out('OK'); return; }
        const m = c.match(/^wr -mb epc -os 2 -d ([0-9A-F]+)$/);
        if (m) { window.__zeti.tags = [m[1]]; out('OK'); return; }
        if (/^(cn|gv)$/.test(c)) { out(c === 'gv' ? 'RFD40 v1' : 'OK'); out('OK'); return; }
        out('ERROR: invalid command');
      } })
    };
    navigator.serial.getPorts = async () => [port];
    navigator.serial.requestPort = async () => port;
  };
}

test('laptop: chip button asks to connect the Zebra when no port is remembered', async ({ page }) => {
  await install(page, { db: DB() });
  await page.addInitScript(() => { window.__asked = 0; navigator.serial.getPorts = async () => []; navigator.serial.requestPort = async () => { window.__asked++; const e = new Error('x'); e.name = 'NotFoundError'; throw e; }; });
  await page.goto('/piece-edit-ar.html?id=p1');
  await page.locator('#gmRfidBtn').click();
  await expect.poll(() => page.evaluate(() => window.__asked)).toBe(1);
});

test('laptop: writes the chip over the COM port, finds the write command and verifies it', async ({ page }) => {
  const patches = [];
  await install(page, { db: DB() });
  page.on('request', r => { if (r.method() === 'PATCH' && r.url().includes('/pieces')) patches.push(r.postDataJSON()); });
  await page.addInitScript(fakeZebra(), { tags: ['E28011700000020A1B2C3D4E'] });
  await page.goto('/piece-edit-ar.html?id=p1');
  await page.waitForFunction(() => typeof currentPiece !== 'undefined' && currentPiece && currentPiece.barcode);
  page.on('dialog', d => d.accept());
  await page.locator('#gmRfidBtn').click();
  await expect.poll(() => patches.length, { timeout: 15000 }).toBe(1);
  const epc = await page.evaluate(() => GMZebra.buildEpcHex('000123', GOLDMIND_STORE_ID).toUpperCase());
  expect(patches[0].rfid_epc.toUpperCase()).toBe(epc);
  expect(await page.evaluate(() => window.__zeti.tags)).toEqual([epc]);
  expect(await page.evaluate(() => localStorage.getItem('gm_zeti_write'))).toBe('wr -mb epc -os 2 -d {D}');
});

test('laptop: refuses to write when two labels are in front of the sled', async ({ page }) => {
  await install(page, { db: DB() });
  await page.addInitScript(fakeZebra(), { tags: ['E28011700000020A1B2C3D4E', 'E28011700000020A1B2C3D4F'] });
  await page.goto('/piece-edit-ar.html?id=p1');
  await page.waitForFunction(() => typeof GMUhf !== 'undefined');
  const err = await page.evaluate(() => GMUhf.writeEpc('AABBCCDDEEFF001122334455').then(() => 'written', e => e.message));
  expect(err).toContain('2 ملصقات');
  expect(await page.evaluate(() => window.__zeti.cmds.some(c => /^wr|^write/.test(c)))).toBe(false);
});
