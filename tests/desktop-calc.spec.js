const { test, expect } = require('@playwright/test');
// Windows "Calculator Pro" shell (desktop/src): a real calculator; only the secret key sequence
// shows the open/change panel. The Tauri bridge is faked here.
async function open(page, storedCode) {
  await page.addInitScript(code => {
    window.__calls = [];
    window.__TAURI__ = { core: { invoke: async (cmd, args) => {
      window.__calls.push([cmd, args || null]);
      if (cmd === 'get_code') return code;
      return null;
    } } };
  }, storedCode || null);
  await page.goto('/desktop/src/index.html');
}

test('works as a scientific calculator', async ({ page }) => {
  await open(page);
  await page.keyboard.type('12+7*2');
  await page.keyboard.press('Enter');
  await expect(page.locator('#display')).toHaveText('26');
  await page.click('[data-k="C"]');
  await page.click('[data-k="9"]'); await page.click('[data-k="÷"]'); await page.click('[data-k="0"]'); await page.click('[data-k="="]');
  await expect(page.locator('#display')).toHaveText('Error');
  // scientific keys: sin(30) + √(16) = 4.5
  for (const k of ['C', 'sin', '3', '0', ')', '+', '√', '1', '6', ')', '=']) await page.click(`[data-k="${k}"]`);
  await expect(page.locator('#display')).toHaveText('4.5');
  for (const k of ['C', '5', '!', '−', '2', '^', '3', '=']) await page.click(`[data-k="${k}"]`);
  await expect(page.locator('#display')).toHaveText('112');
});

test('wrong sequence shows nothing, default sequence opens the gate', async ({ page }) => {
  await open(page);
  await page.keyboard.press('ArrowDown'); await page.keyboard.type('2026'); await page.keyboard.press('Enter');
  await expect(page.locator('#gate')).toHaveClass(/\bhidden\b/);
  await page.keyboard.press('ArrowDown'); await page.keyboard.press('ArrowDown');
  await page.keyboard.type('2026'); await page.keyboard.press('Enter');
  await expect(page.locator('#gate')).not.toHaveClass(/\bhidden\b/);
  await page.click('#gate-open');
  expect(await page.evaluate(() => window.__calls.map(c => c[0]))).toContain('open_app');
});

test('change the secret sequence', async ({ page }) => {
  await open(page);
  for (const k of ['ArrowDown', 'ArrowDown', '2', '0', '2', '6', 'Enter']) await page.keyboard.press(k);
  await page.click('#gate-change');
  const seq = ['ArrowUp', '1', '2', 'ArrowLeft', 'Enter'];
  for (const k of seq) await page.keyboard.press(k);
  await expect(page.locator('#ns-title')).toContainText('للتأكيد');
  for (const k of seq) await page.keyboard.press(k);
  await expect(page.locator('#gate-msg')).toHaveText('تم حفظ الرمز الجديد.');
  const saved = await page.evaluate(() => window.__calls.find(c => c[0] === 'set_code')[1].value);
  expect(saved).toMatch(/^5:[0-9a-f]{64}$/);

  // Next start: the old default no longer opens anything, the new one does.
  const page2 = await page.context().newPage();
  await open(page2, saved);
  for (const k of ['ArrowDown', 'ArrowDown', '2', '0', '2', '6', 'Enter']) await page2.keyboard.press(k);
  await expect(page2.locator('#gate')).toHaveClass(/\bhidden\b/);
  for (const k of seq) await page2.keyboard.press(k);
  await expect(page2.locator('#gate')).not.toHaveClass(/\bhidden\b/);
});

// بشار 2026-11-22: on an Arabic keyboard layout the digit keys send ٢٠٢٦ — the code must still open.
test('secret sequence typed with Arabic-Indic digits opens the panel', async ({ page }) => {
  await open(page);
  await page.keyboard.press('ArrowDown'); await page.keyboard.press('ArrowDown');
  await page.evaluate(() => ['٢', '٠', '٢', '٦'].forEach((k, i) => document.dispatchEvent(new KeyboardEvent('keydown', { key: k, code: 'Digit' + '2026'[i], bubbles: true }))));
  await page.keyboard.press('Enter');
  await expect(page.locator('#gate')).not.toHaveClass(/\bhidden\b/);
});
