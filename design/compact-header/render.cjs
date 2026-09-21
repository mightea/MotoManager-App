const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(require.resolve('@playwright/test', {
  paths: [path.resolve(__dirname, '../../../MotoManager')],
}));

(async () => {
  const browser = await chromium.launch({ headless: true, channel: 'chrome' });
  const page = await browser.newPage({ viewport: { width: 1620, height: 1170 }, deviceScaleFactor: 2 });
  const url = pathToFileURL(path.join(__dirname, 'mockup.html')).href;
  await page.goto(url);
  await page.screenshot({ path: path.join(__dirname, 'comparison.png'), fullPage: true });
  await page.locator('#phone [data-bike]').click();
  if (!await page.locator('#phone .modal').isVisible()) throw new Error('Motorcycle picker did not open');
  await page.keyboard.press('Escape');
  const before = await page.locator('#phone .chrome').boundingBox();
  await page.locator('#phone .scroll').evaluate(el => { el.scrollTop = 200; });
  const after = await page.locator('#phone .chrome').boundingBox();
  if (before.y !== after.y) throw new Error('Motorcycle header moved while scrolling');
  for (const [device, width, height] of [['phone', 390, 844], ['tablet', 1180, 820]]) {
    await page.setViewportSize({ width, height });
    await page.goto(url + '?device=' + device);
    await page.screenshot({ path: path.join(__dirname, device + '.png'), fullPage: true });
  }
  console.log('Rendered comparison.png, phone.png and tablet.png; verified picker and persistent header.');
  await browser.close();
})();
