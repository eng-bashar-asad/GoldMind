const { test, expect } = require('@playwright/test');
// Windows "Calculator Pro" shell (desktop/src): a real calculator; only the secret key sequence
// opens the program (Shift+Enter: change the code). The Tauri bridge is faked here.
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

test('wrong sequence shows nothing, the secret sequence opens the program at once', async ({ page }) => {
  await open(page);
  await page.keyboard.press('ArrowDown'); await page.keyboard.type('2026'); await page.keyboard.press('Enter');
  await expect(page.locator('#gate')).toHaveClass(/\bhidden\b/);
  expect(await page.evaluate(() => window.__calls.map(c => c[0]))).not.toContain('open_app');
  await page.keyboard.press('ArrowDown'); await page.keyboard.press('ArrowDown');
  await page.keyboard.type('2026'); await page.keyboard.press('Enter');
  await expect.poll(() => page.evaluate(() => window.__calls.map(c => c[0]))).toContain('open_app');
  await expect(page.locator('#gate')).toHaveClass(/\bhidden\b/);
  await expect(page.locator('#newseq')).toHaveClass(/\bhidden\b/);
});

// بشار 2026-11-26: the code ending with Shift+Enter opens "change the code" instead of the program.
test('change the secret sequence with Shift+Enter', async ({ page }) => {
  await open(page);
  for (const k of ['ArrowDown', 'ArrowDown', '2', '0', '2', '6', 'Shift+Enter']) await page.keyboard.press(k);
  await expect(page.locator('#newseq')).not.toHaveClass(/\bhidden\b/);
  expect(await page.evaluate(() => window.__calls.map(c => c[0]))).not.toContain('open_app');
  const seq = ['ArrowUp', '1', '2', 'ArrowLeft', 'Enter'];
  for (const k of seq) await page.keyboard.press(k);
  await expect(page.locator('#ns-title')).toContainText('للتأكيد');
  for (const k of seq) await page.keyboard.press(k);
  await expect.poll(() => page.evaluate(() => window.__calls.map(c => c[0]))).toContain('open_app');
  const saved = await page.evaluate(() => window.__calls.find(c => c[0] === 'set_code')[1].value);
  expect(saved).toMatch(/^5:[0-9a-f]{64}$/);

  // Next start: the old default no longer opens anything, the new one does.
  const page2 = await page.context().newPage();
  await open(page2, saved);
  for (const k of ['ArrowDown', 'ArrowDown', '2', '0', '2', '6', 'Enter']) await page2.keyboard.press(k);
  await page2.waitForTimeout(200);
  expect(await page2.evaluate(() => window.__calls.map(c => c[0]))).not.toContain('open_app');
  for (const k of seq) await page2.keyboard.press(k);
  await expect.poll(() => page2.evaluate(() => window.__calls.map(c => c[0]))).toContain('open_app');
});

// Sent back from GoldMind's settings (index.html#change): straight to the change screen; cancel returns to the program.
test('change screen opened from the program', async ({ page }) => {
  await page.addInitScript(() => {
    window.__calls = [];
    window.__TAURI__ = { core: { invoke: async (cmd, args) => { window.__calls.push([cmd, args || null]); return null; } } };
  });
  await page.goto('/desktop/src/index.html#change');
  await expect(page.locator('#newseq')).not.toHaveClass(/\bhidden\b/);
  await page.click('#ns-cancel');
  await expect.poll(() => page.evaluate(() => window.__calls.map(c => c[0]))).toContain('open_app');
});

// بشار 2026-11-22: on an Arabic keyboard layout the digit keys send ٢٠٢٦ — the code must still open.
test('secret sequence typed with Arabic-Indic digits opens the program', async ({ page }) => {
  await open(page);
  await page.keyboard.press('ArrowDown'); await page.keyboard.press('ArrowDown');
  await page.evaluate(() => ['٢', '٠', '٢', '٦'].forEach((k, i) => document.dispatchEvent(new KeyboardEvent('keydown', { key: k, code: 'Digit' + '2026'[i], bubbles: true }))));
  await page.keyboard.press('Enter');
  await expect.poll(() => page.evaluate(() => window.__calls.map(c => c[0]))).toContain('open_app');
});
