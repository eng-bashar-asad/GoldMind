// بشار 2026-11-23: a number with its own international prefix (00905454888969 — Turkey) is kept
// as typed for WhatsApp / printing, whatever code is picked next to it; Turkey is in the pickers by name.
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
test('international numbers and the Turkey code', async ({ page }) => {
  await install(page, { generic: true, db: { stores: [{ id: STORE, name: 'x', currency: 'USD', country: 'SY' }],
    staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {} }], user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] } });
  await page.goto('/customer-add-ar.html');
  const r = await page.evaluate(() => ({
    typed00: gmIntlPhone('00905454888969', 'SY'),
    typedPlus: gmIntlPhone('+90 545 488 8969', '963'),
    localTr: gmIntlPhone('05454888969', '90'),
    localSy: gmIntlPhone('0933000960', 'SY'),
    already: gmIntlPhone('963933000960', 'SY'),
    arabic: gmIntlPhone('٠٠٩٠٥٤٥٤٨٨٨٩٦٩', 'AE'),
    wa: gmWhatsAppUrl('00905454888969', 'SY', 'hi'),
  }));
  expect(r).toEqual({ typed00: '905454888969', typedPlus: '905454888969', localTr: '905454888969', localSy: '963933000960',
    already: '963933000960', arabic: '905454888969', wa: 'https://wa.me/905454888969?text=hi' });
  await expect(page.locator('#individual-phone-code option[value="90"]')).toHaveText('+90 تركيا');
});
