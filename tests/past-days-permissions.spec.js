// Daily cash box, past days: browsing, editing and back-dating each need their own permission;
// a back-dated add asks first; "وقت الإدخال" shows when a row was really typed in.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');

const daysAgo = n => { const d = new Date(); d.setDate(d.getDate() - n); d.setHours(12, 0, 0, 0); return d; };
const ymd = d => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');

function db(role, permissions, extraRows = []) {
  return {
    stores: [{ id: STORE, name: 'محل', currency: 'AED' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role, permissions, full_name: 'موظف' }],
    user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }],
    daily_cash_log: [
      { id: 'old1', store_id: STORE, direction: 'in', amount: 700, currency: 'AED', operation_type: 'قديمة', created_at: daysAgo(3).toISOString(), entered_at: daysAgo(2).toISOString() },
      { id: 'now1', store_id: STORE, direction: 'out', amount: 5, currency: 'AED', operation_type: 'ضيافة', created_at: new Date().toISOString(), entered_at: new Date().toISOString() },
      ...extraRows],
  };
}

test('employee without past-day permissions: no day arrows, no date field, cannot open a past row', async ({ page }) => {
  await install(page, { db: db('staff', { manage_daily_cashbox: true, view_past_days: true }) });
  await page.goto('/daily-cashbox-ar.html');
  await page.waitForFunction(() => typeof allEntries !== 'undefined' && allEntries.length === 2);
  await expect(page.locator('#day-nav')).toHaveClass(/\bhidden\b/); // view_past_days alone no longer opens the cash box days
  expect(await page.evaluate(() => [canSeeDays, canManageDates, canEditPast])).toEqual([false, false, false]);
  page.once('dialog', d => d.accept());
  await page.evaluate(() => openEditModal('old1'));
  await expect(page.locator('#editModal')).toHaveClass(/\bhidden\b/);
});

test('back-dating asks first; cancelling saves nothing', async ({ page }) => {
  const calls = [];
  await install(page, { db: db('staff', { manage_daily_cashbox: true, backdate_entries: true, view_past_cashbox: true }), calls });
  await page.goto('/daily-cashbox-ar.html');
  await page.waitForFunction(() => typeof allEntries !== 'undefined' && allEntries.length === 2);
  await page.evaluate(() => { if (document.getElementById('addForm').classList.contains('hidden')) toggleAddForm(); });
  await page.fill('#opTypeInput', 'تجربة');
  await page.fill('#amountInput', '10');
  let asked = '';
  page.once('dialog', d => { asked = d.message(); d.dismiss(); });
  // set the date in the same tick as the save (a late re-render puts the selected day back)
  await page.evaluate(d => { document.getElementById('addFormDate').value = d; return submitEntry(); }, ymd(daysAgo(4)));
  expect(asked).toContain('بتاريخ سابق');
  expect(await page.evaluate(() => allEntries.length)).toBe(2);
});

test('"وقت الإدخال" shows the real entry time and marks rows typed in on a later day', async ({ page }) => {
  await install(page, { db: db('owner', {}) });
  await page.goto('/daily-cashbox-ar.html');
  await page.waitForFunction(() => typeof allEntries !== 'undefined' && allEntries.length === 2);
  await page.evaluate(() => { try { localStorage.removeItem('gm_dc_entered'); } catch (_) {} });
  await page.evaluate(() => { showFullHistory = false; toggleFullHistory(); });
  await expect(page.locator('[data-entry="old1"]')).not.toContainText('أُدخلت');
  await page.click('#dcEnteredBtn');
  await expect(page.locator('#dcEnteredBtn')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('[data-entry="old1"]')).toContainText('بتاريخ سابق');
  await expect(page.locator('[data-entry="now1"]')).toContainText('أُدخلت');
  await expect(page.locator('[data-entry="now1"]')).not.toContainText('بتاريخ سابق');
});
