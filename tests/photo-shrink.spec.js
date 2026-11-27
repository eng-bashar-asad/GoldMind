// Piece photos are shrunk before upload, and the owner tool converts existing photos (keeping the originals).
const { test, expect } = require('@playwright/test');
const { install, STORE, USER, STAFF } = require('./fake-backend');
const base = { stores: [{ id: STORE, name: 'محل', currency: 'AED' }], staff: [{ id: STAFF, user_id: USER, store_id: STORE, role: 'owner', permissions: {}, full_name: 'بشار' }],
  user_profiles: [{ id: USER, privacy_accepted_at: '2026-01-01' }] };
// a 2400×1600 photo-like PNG (noise compresses badly, like a real camera photo)
const bigPng = page => page.evaluate(() => { const c = document.createElement('canvas'); c.width = 2400; c.height = 1600; const x = c.getContext('2d');
  const d = x.createImageData(2400, 1600); for (let i = 0; i < d.data.length; i += 4) { const v = (i / 4) % 2400 / 10; d.data[i] = 200 + Math.random() * 55; d.data[i + 1] = 150 + v % 60; d.data[i + 2] = 60 + Math.random() * 40; d.data[i + 3] = 255; }
  x.putImageData(d, 0, 0); return c.toDataURL('image/png').split(',')[1]; });

test('uploads to piece-photos are shrunk to 1200px JPEG', async ({ page }) => {
  await install(page, { generic: true, db: base });
  const ups = [];
  await page.route(/storage\/v1\/object\/piece-photos\//, async r => { const b = r.request().postDataBuffer(); ups.push({ type: r.request().headers()['content-type'], cache: r.request().headers()['cache-control'] || ((b && b.toString('latin1').match(/name="cacheControl"\r\n\r\n([^\r]+)/)) || [])[1], size: b ? b.length : 0 }); r.fulfill({ json: { Key: 'x' } }); });
  await page.goto('/settings-ar.html');
  const b64 = await bigPng(page);
  const res = await page.evaluate(async b64 => {
    const bin = Uint8Array.from(atob(b64), c => c.charCodeAt(0)); const f = new File([bin], 'cam.png', { type: 'image/png' });
    const s = await gmShrinkPhoto(f); const bmp = await createImageBitmap(s);
    await goldmindClient.storage.from('piece-photos').upload(GOLDMIND_STORE_ID + '/G1-1.png', f, { upsert: false });
    const logo = new File([bin], 'l.png', { type: 'image/png' });
    return { before: f.size, after: s.size, type: s.type, w: bmp.width, h: bmp.height, same: (await gmShrinkPhoto(new File(['x'], 'a.heic', { type: 'image/heic' }))).name };
  }, b64);
  expect(res.type).toBe('image/jpeg');
  expect(Math.max(res.w, res.h)).toBe(1200);
  expect(res.after).toBeLessThan(res.before / 3);
  expect(res.same).toBe('a.heic'); // undecodable formats go up unchanged
  expect(ups).toHaveLength(1);
  expect(ups[0].size).toBeLessThan(res.before / 3);
  expect(String(ups[0].cache)).toMatch(/31536000/); // devices keep a photo a year instead of re-downloading it hourly
});

