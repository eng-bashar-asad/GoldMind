const { test, expect } = require('@playwright/test');
const { install } = require('./fake-backend');

async function setup(page) {
  await install(page, {});
  await page.goto('/tests/harness.html');
  await page.evaluate(() => {
    document.body.insertAdjacentHTML('beforeend',
      '<input type="file" accept="image/*" capture="environment" id="cam" style="display:none">' +
      '<button id="btn" onclick="document.getElementById(\'cam\').click()">صورة</button>');
  });
}

// Camera window (gm-camera.js): "اختيار صورة من الجهاز" opens the picker without the camera; ✕ just closes.
test.use({ launchOptions: { args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream'] }, permissions: ['camera'] });
  async function openCam(page) {
    await setup(page);
    await page.addScriptTag({ url: '/gm-camera.js' });
    await page.evaluate(() => {
      document.getElementById('btn').onclick = async () => {
        const f = await GMCamera.capture();
        window.__res = f === false ? 'closed' : f ? 'file' : 'picker';
        if (f === false || f) return;
        document.getElementById('cam').click();
      };
    });
    await page.click('#btn');
    await expect(page.getByText('اختيار صورة من الجهاز')).toBeVisible();
  }
  test('choose from device opens the file picker (no camera capture)', async ({ page }) => {
    await openCam(page);
    const [chooser] = await Promise.all([page.waitForEvent('filechooser', { timeout: 3000 }), page.getByText('اختيار صورة من الجهاز').click()]);
    expect(chooser).toBeTruthy();
    expect(await page.evaluate(() => document.getElementById('cam').hasAttribute('capture'))).toBe(false);
    await expect(page.locator('#gm-photo-sheet')).toHaveCount(0);
    await expect.poll(() => page.evaluate(() => document.getElementById('cam').getAttribute('capture')), { timeout: 3000 }).toBe('environment');
  });
  test('✕ closes the camera without opening anything', async ({ page }) => {
    await openCam(page);
    let opened = false; page.on('filechooser', () => { opened = true; });
    await page.click('button[aria-label="إلغاء"]');
    await expect.poll(() => page.evaluate(() => window.__res)).toBe('closed');
    await page.waitForTimeout(300);
    await expect(page.locator('#gm-photo-sheet')).toHaveCount(0);
    expect(opened).toBe(false);
  });
