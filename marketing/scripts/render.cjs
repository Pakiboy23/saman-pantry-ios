// Headless renderer for the marketing HTML sources.
// Every frame is rendered deterministically by pausing all CSS animations and
// seeking them to the frame's time, so output never depends on machine speed.
//
//   node render.cjs still <html> <out.png> <width> <height> [scale]
//   node render.cjs frames <html> <outPrefix> <count> [fps]
//     (1920x1080; writes <outPrefix>_000.png ...)
const { chromium } = require('playwright');
const path = require('node:path');

const [mode, html, out, a, b, c] = process.argv.slice(2);
const url = html.includes('://') ? html : 'file://' + path.resolve(html.split('?')[0]) + (html.includes('?') ? '?' + html.split('?')[1] : '');

(async () => {
const browser = await chromium.launch();
if (mode === 'still') {
  const [w, h, scale] = [+a, +b, +(c || 3)];
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale });
  await page.goto(url, { waitUntil: 'load' });
  await page.evaluate(async () => { await document.fonts.ready; });
  await page.waitForTimeout(300);
  const el = (await page.$('.canvas')) || (await page.$('body'));
  await el.screenshot({ path: out });
} else if (mode === 'frames') {
  const [count, fps] = [+a, +(b || 30)];
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  await page.goto(url, { waitUntil: 'load' });
  await page.evaluate(async () => { await document.fonts.ready; });
  await page.evaluate(() => document.body.classList.add('play'));
  for (let i = 0; i < count; i++) {
    await page.evaluate((t) => document.getAnimations().forEach((an) => { an.pause(); an.currentTime = t; }), (i * 1000) / fps);
    await page.screenshot({ path: `${out}_${String(i).padStart(3, '0')}.png` });
  }
} else {
  console.error('usage: render.cjs still|frames ...'); process.exit(2);
}
await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
