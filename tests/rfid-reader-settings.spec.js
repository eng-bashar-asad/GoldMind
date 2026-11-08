// Reader settings page: saves powers / trigger on this device; on a computer connects the Zebra over COM.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const db = () => ({
  stores: [{ id: STORE, name: 'x', currency: 'USD', rfid_enabled: true }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  pieces: [{ id: 'p1', store_id: STORE, barcode: '000805', description_ar: 'خاتم', status: 'available', rfid_epc: 'E28011700000020A1B2C3D4E' }],
});

test('powers and trigger are saved; read test names the piece of a known chip', async ({ page }) => {
  await install(page, { db: db() });
  await page.addInitScript(() => {
    navigator.serial.getPorts = async () => [];
    navigator.serial.requestPort = async () => ({ getInfo: () => ({}), open: async () => {}, close: async () => {},
      readable: new ReadableStream({ start(c) { window.__out = s => c.enqueue(new TextEncoder().encode(s + '\r\n')); } }),
      writable: new WritableStream({ write(ch) { const c = new TextDecoder().decode(ch).trim();
        if (c === 'in') window.__inv = setInterval(() => window.__out('E28011700000020A1B2C3D4E'), 100);
        else { if (c === 'a') clearInterval(window.__inv); window.__out(c === 'gv' ? 'RFD40 v1.0' : 'OK'); } } }) });
  });
  await page.goto('/rfid-reader-settings-ar.html');
  await expect(page.locator('#rsStatus')).toHaveText('غير متصل');
  await page.locator('#rsWrite').fill('9');
  await page.locator('#rsTrigger [data-trigger="toggle"]').click();
  const s = await page.evaluate(() => JSON.parse(localStorage.getItem('gm_rfid_settings')));
  expect(s.writePower).toBe(9); expect(s.trigger).toBe('toggle');
  await page.locator('#rsConnect').click();
  await expect(page.locator('#rsStatus')).toContainText('متصل');
  await page.locator('#rsRead1').click();
  await expect(page.locator('#rsList')).toContainText('000805');
});
