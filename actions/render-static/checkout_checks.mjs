import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile, stat, realpath } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { chromium } from 'playwright';
import { matchesPath, safeUrl } from './policy.mjs';

const config = JSON.parse(await readFile(process.env.RENDER_DEPLOY_CONFIG || 'deploy/render.json', 'utf8'));
const plan = JSON.parse(await readFile('deployment-evidence/plan.json', 'utf8'));
const mode = process.argv[2];
assert(['local', 'live'].includes(mode), 'Expected local or live check mode');
await mkdir('deployment-evidence/screenshots', { recursive: true });

const mimeTypes = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'application/javascript',
  '.json': 'application/json', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.avif': 'image/avif',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.woff2': 'font/woff2', '.woff': 'font/woff',
  '.mp3': 'audio/mpeg', '.xml': 'application/xml', '.ico': 'image/x-icon', '.pdf': 'application/pdf', '.txt': 'text/plain',
};

let server;
let origin = config.origin;
let localOrigin;
if (mode === 'local') {
  const root = resolve(config.publish_path);
  server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://127.0.0.1');
      let path = resolve(root, `.${decodeURIComponent(url.pathname)}`);
      assert(path === root || path.startsWith(root + sep), 'Path outside publish directory');
      try { if ((await stat(path)).isDirectory()) path = resolve(path, 'index.html'); }
      catch { if (!extname(path)) path += '.html'; }
      const actual = await realpath(path);
      assert(actual.startsWith((await realpath(root)) + sep), 'Symlink outside publish directory');
      const body = await readFile(path);
      const headers = { 'Content-Type': mimeTypes[extname(path)] || 'application/octet-stream' };
      for (const rule of plan.desired) if (matchesPath(rule.path, url.pathname)) {
        assert(!headers[rule.name], `Overlapping ${rule.name} rules require explicit precedence`);
        headers[rule.name] = rule.value;
      }
      response.writeHead(200, headers); response.end(body);
    } catch {
      response.writeHead(404, { 'Content-Type': 'text/plain' }); response.end('Resource unavailable');
    }
  });
  await new Promise(resolveListen => server.listen(0, '127.0.0.1', resolveListen));
  localOrigin = `http://127.0.0.1:${server.address().port}`;
}

const browser = await chromium.launch({ headless: true });
const results = [];
const failures = [];
const redact = text => text.replace(/https?:\/\/[^\s'";]+/g, url => {
  try { return safeUrl(url); } catch { return '<url>'; }
});

async function newContext() {
  const context = await browser.newContext();
  if (mode === 'local') {
    // Retain the production origin so absolute first-party URLs and
    // CSP 'self' behave exactly as they do after deployment.
    await context.route(`${config.origin}/**`, async route => {
      const source = new URL(route.request().url());
      const response = await context.request.get(`${localOrigin}${source.pathname}${source.search}`);
      await route.fulfill({ response });
    });
  }
  return context;
}

async function inspectHeaders(context, path) {
  const url = new URL(path, mode === 'local' ? localOrigin : origin).href;
  const deadline = Date.now() + (mode === 'live' ? 60000 : 0);
  while (true) {
    try {
      const response = await context.request.get(url, { timeout: 30000, headers: { 'Cache-Control': 'no-cache' } });
      assert.equal(response.status(), 200, `HTTP ${response.status()} for ${path}`);
      const actual = response.headers();
      for (const rule of plan.desired.filter(r => matchesPath(r.path, new URL(url).pathname))) {
        assert.equal(actual[rule.name.toLowerCase()], rule.value, `Header ${rule.name} differs on ${path}`);
      }
      return;
    } catch (error) {
      if (Date.now() >= deadline) throw error;
      await new Promise(done => setTimeout(done, 2000));
    }
  }
}

async function openPage(context, path, violations) {
  const page = await context.newPage();
  page.setDefaultTimeout(30000);
  page.on('console', message => {
    // Checkout providers manage their own policies. Gate violations caused
    // by the site's policy, including its embedded Shopify frames.
    if (page.url().startsWith(config.origin + '/') && /violat.*(?:content.security.policy|csp)|content.security.policy.*violat/i.test(message.text())) {
      violations.push(redact(message.text()));
    }
  });
  const response = await page.goto(new URL(path, origin).href, { waitUntil: 'domcontentloaded' });
  assert.equal(response.status(), 200, `Page failed: ${path}`);
  await page.locator('body').waitFor({ state: 'visible' });
  return page;
}

async function shopify(context, test, violations) {
  const page = await openPage(context, test.path, violations);
  const product = page.locator(`[data-product-id="${test.product_id}"]`);
  assert.equal(await product.count(), 1, 'Configured Shopify product is missing or duplicated');
  const inline = product.getByRole('button', { name: /^Add (?:PDF )?to cart$/ });
  if (test.inline) await inline.click();
  else await page.frameLocator(`iframe[name="frame-product-${test.product_id}"]`).getByRole('button', { name: /^Add (?:PDF )?to cart$/ }).click();
  const cart = page.frameLocator('iframe[name="frame-cart"]');
  await cart.getByText(test.product_name, { exact: true }).waitFor({ state: 'visible' });
  const checkout = cart.getByRole('button', { name: 'Checkout', exact: true });
  assert(await checkout.isEnabled(), 'Shopify checkout button is disabled');
  await page.screenshot({ path: `deployment-evidence/screenshots/${mode}-${test.id}-cart.png` });
  await checkout.click();
  await page.waitForURL(url => url.protocol === 'https:' && url.hostname === test.checkout_host && url.pathname.startsWith('/checkouts/'), { timeout: 60000 });
  await page.getByRole('heading', { name: /Checkout/i }).first().waitFor({ state: 'visible' });
  await page.frameLocator('iframe[name^="card-fields-number-"]').getByRole('textbox', { name: 'Card number', exact: true }).waitFor({ state: 'visible' });
  await page.screenshot({ path: `deployment-evidence/screenshots/${mode}-${test.id}-checkout.png` });
  results.push({ id: test.id, provider: 'shopify', stage: 'card entry', checkout: safeUrl(page.url()) });
  // Every test has a fresh anonymous context; remove only its test item.
  await page.goto(new URL(test.path, origin).href);
  await page.getByRole('button', { name: 'cart', exact: true }).click();
  await page.frameLocator('iframe[name="frame-cart"]').getByRole('button', { name: 'Reduce item quantity by one', exact: true }).click();
  await page.frameLocator('iframe[name="frame-cart"]').getByText('Your cart is empty.', { exact: true }).waitFor({ state: 'visible' });
}

async function folio(context, test, violations) {
  const page = await openPage(context, test.path, violations);
  const link = page.locator(`a[href="${test.buy_url}"]`);
  assert.equal(await link.count(), 1, 'Configured Folio purchase link is missing or duplicated');
  const buy = new URL(await link.getAttribute('href'), origin);
  assert.equal(buy.origin, test.checkout_origin, 'Unexpected Folio purchase origin');
  const [checkout] = await Promise.all([context.waitForEvent('page'), link.click()]);
  checkout.setDefaultTimeout(30000);
  await checkout.waitForURL(url => url.origin === test.checkout_origin && url.pathname.startsWith('/checkout/'), { timeout: 60000 });
  await checkout.getByRole('heading', { name: 'Checkout', exact: true }).waitFor({ state: 'visible' });
  await checkout.getByRole('cell', { name: test.product_name, exact: true }).waitFor({ state: 'visible' });
  await checkout.frameLocator('iframe[title="Secure payment input frame"]').getByRole('textbox', { name: 'Card number', exact: true }).waitFor({ state: 'visible' });
  await checkout.screenshot({ path: `deployment-evidence/screenshots/${mode}-${test.id}-checkout.png` });
  results.push({ id: test.id, provider: 'folio', stage: 'Stripe card entry', checkout: safeUrl(checkout.url()) });
  await checkout.close();
}

try {
  const smokeContext = await newContext();
  const smokeViolations = [];
  await inspectHeaders(smokeContext, '/');
  const smoke = await openPage(smokeContext, '/', smokeViolations);
  await smoke.waitForLoadState('load');
  const assets = await smoke.locator('link[rel="stylesheet"],script[src]').evaluateAll(elements => elements.map(e => e.getAttribute('href') || e.getAttribute('src')).filter(u => u?.startsWith('/assets/')));
  for (const asset of assets.slice(0,3)) await inspectHeaders(smokeContext, asset);
  if (config.require_fingerprinted_fonts) {
    assert(assets.some(u => /^\/assets\/fonts\/fonts\.[a-f0-9]{10}\.css$/.test(u)), 'Missing fingerprinted font stylesheet');
    assert(!assets.includes('/assets/fonts/fonts.css'), 'Fixed font stylesheet URL would retain stale cached styling');
  }
  assert.deepEqual(smokeViolations, [], 'CSP violations on the homepage');
  results.push({ id: 'homepage', stage: 'HTTP headers and CSP', passed: true });
  await smokeContext.close();
  for (const test of config.commerce_tests || []) {
    const context = await newContext();
    const violations = [];
    try {
      await inspectHeaders(context, test.path);
      if (test.provider === 'shopify') await shopify(context, test, violations);
      else if (test.provider === 'folio') await folio(context, test, violations);
      else throw new Error(`Unsupported checkout provider: ${test.provider}`);
      assert.deepEqual(violations, [], `CSP violations in ${test.id}`);
      console.log(`${mode}: ${test.id} checkout reached card entry`);
    } catch (error) {
      const page = context.pages()[0];
      const frames = page ? page.frames().map(frame => ({ name: frame.name(), url: redact(frame.url()) })) : [];
      failures.push({ id: test.id, message: redact(error.message), csp_violations: violations, frames });
      if (page) await page.screenshot({ path: `deployment-evidence/screenshots/${mode}-${test.id}-failed.png`, timeout: 5000 }).catch(() => {});
    } finally { await context.close(); }
  }
  assert.equal(failures.length, 0, `${failures.length} checkout check(s) failed`);
} catch (error) {
  failures.push({ id: 'deployment-check', message: redact(error.message) });
  process.exitCode = 1;
} finally {
  await writeFile(`deployment-evidence/${mode}-checks.json`, JSON.stringify({ mode, results, failures, payments_submitted: false }, null, 2));
  await browser.close();
  if (server) await new Promise(resolveClose => server.close(resolveClose));
}
