import assert from 'node:assert/strict';

export async function waitForFolioPurchaseLink(page, buyUrl) {
  const link = page.locator(`a[href="${buyUrl}"]`);
  // Live catalogs populate and reveal purchase links after DOMContentLoaded.
  await link.first().waitFor({ state: 'visible' });
  assert.equal(await link.count(), 1, 'Configured Folio purchase link is missing or duplicated');
  return link;
}
