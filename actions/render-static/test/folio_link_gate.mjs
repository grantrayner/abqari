import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { browserOptions } from '../browser_options.mjs';
import { waitForFolioPurchaseLink } from '../folio_purchase_link.mjs';

const browser = await chromium.launch(browserOptions(process.env.RENDER_CHECK_BROWSER));
const url = 'https://folio.example/buy/author/publication/book';
try {
  const page = await browser.newPage();
  page.setDefaultTimeout(2000);
  await page.setContent(`<a hidden data-buy>Buy</a><script>
    setTimeout(() => { const link = document.querySelector('[data-buy]');
      link.href = ${JSON.stringify(url)}; link.hidden = false; }, 100);
  </script>`);
  const link = await waitForFolioPurchaseLink(page, url);
  assert.equal(await link.getAttribute('href'), url);

  await page.setContent(`<a href="${url}">Buy</a><a href="${url}">Duplicate</a>`);
  await assert.rejects(waitForFolioPurchaseLink(page, url), /missing or duplicated/);

  page.setDefaultTimeout(100);
  await page.setContent(`<a hidden href="${url}">Unavailable</a>`);
  await assert.rejects(waitForFolioPurchaseLink(page, url), /Timeout/);
  await page.setContent('<p>Catalog failed</p>');
  await assert.rejects(waitForFolioPurchaseLink(page, url), /Timeout/);
  console.log('Folio gate waits for delayed links and rejects duplicates, hidden and absent links');
} finally {
  await browser.close();
}
