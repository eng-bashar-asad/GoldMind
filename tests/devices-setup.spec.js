// Device setup page: Zebra printer pick + per-computer label tweaks, and the RFID read test.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const db = () => ({
  stores: [{ id: STORE, name: 'محل', currency: 'USD', zebra_label_width_mm: 50, zebra_label_height_mm: 25, zebra_label_dpi: 203, zebra_darkness: 15 }],
  staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
  zebra_label_fields: [],
  pieces: [{ id: 'p1', store_id: STORE, barcode: '000856', description_ar: 'خاتم', rfid_epc: '111111110000000000000856' }]
});

async function fakeZebra(page) {
  await page.addInitScript(() => {
    window.__zpl = [];
    const dev = uid => ({ uid, name: uid, deviceType: 'printer', send: (z, ok) => { window.__zpl.push({ uid, z }); ok(); } });
    window.BrowserPrint = {
      getLocalDevices: ok => ok([dev('ZD421-A'), dev('ZD421-B')]),
      getDefaultDevice: (t, ok) => ok(dev('ZD421-A'))
    };
  });
}

test('zebra: pick a printer, test print with this computer\'s darkness, save', async ({ page }) => {
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await fakeZebra(page);
  await install(page, { db: db() });
  await page.goto('/devices-setup-ar.html?device=printer');
  await page.click('[data-brand="zebra"]');
  await expect(page.locator('#bp-status')).toContainText('2 طابعات');
  await page.selectOption('#printer-select', 'ZD421-B');
  await page.fill('#d-darkness', '22');
  await page.click('[data-nudge="d-x"][data-by="0.5"]');
  await expect(page.locator('#d-x')).toHaveValue('0.5');
  await page.click('#zebra-test');
  await expect(page.locator('#zebra-msg')).toContainText('أُرسل');
  const sent = await page.evaluate(() => window.__zpl);
  expect(sent).toHaveLength(1);
  expect(sent[0].uid).toBe('ZD421-B');
  expect(sent[0].z).toContain('^MD22');
  // a test print alone doesn't change what's saved
  expect(await page.evaluate(() => GMZebra.deviceSettings().darkness)).toBeUndefined();
  await page.click('#zebra-save');
  const saved = await page.evaluate(() => GMZebra.deviceSettings());
  expect(saved).toMatchObject({ printer_uid: 'ZD421-B', darkness: 22, x_offset_mm: 0.5, dpi: null });
  // other pages read the store through withDevice
  const merged = await page.evaluate(() => GMZebra.withDevice({ zebra_darkness: 15, zebra_label_dpi: 203, zebra_label_x_offset_mm: 0 }));
  expect(merged).toEqual({ zebra_darkness: 22, zebra_label_dpi: 203, zebra_label_x_offset_mm: 0.5 });
  expect(errs).toEqual([]);
});

test('rfid: a keyboard-mode reader is detected and a shop tag names its piece', async ({ page }) => {
  await install(page, { db: db() });
  await page.goto('/devices-setup-ar.html?device=rfid');
  await page.click('[data-reader="usb"]');
  await page.locator('#rfid-test').fill('111111110000000000000856');
  await page.locator('#rfid-test').press('Enter');
  await expect(page.locator('#rfid-result')).toContainText('القارئ يعمل');
  await expect(page.locator('#rfid-list')).toContainText('خاتم');
  // no Enter from the reader: still read after a short pause
  await page.locator('#rfid-test').fill('E2801160600002');
  await expect(page.locator('#rfid-result')).toContainText('2');
});
