import test from 'node:test';
import assert from 'node:assert/strict';
import { matchesPath, safeUrl, headerMismatches } from '../policy.mjs';

test('global and nested prefix header rules cover their intended request paths', () => {
  assert(matchesPath('/*', '/publications/example/'));
  assert(matchesPath('/assets/*', '/assets/fonts/fonts.abcdef1234.css'));
  assert(!matchesPath('/assets/*', '/lessons/example/'));
  assert(matchesPath('/news.xml', '/news.xml'));
  assert(!matchesPath('/news.xml', '/news+xml'));
});

test('extension wildcard does not leak into nested directories', () => {
  assert(matchesPath('/*.css', '/app.css'));
  assert(!matchesPath('/*.css', '/assets/app.css'));
  assert(matchesPath('/assets/*.css', '/assets/app.css'));
});

test('checkout session tokens and query parameters are never copied into results', () => {
  assert.equal(safeUrl('https://www.foliobooks.app/checkout/private-token?secret=hidden'), 'https://www.foliobooks.app/checkout/<redacted>');
  assert.equal(safeUrl('https://store.myshopify.com/checkouts/cn/private-token/en?secret=hidden'), 'https://store.myshopify.com/checkouts/<redacted>');
  assert.equal(safeUrl('https://example.com/cart/private-token'), 'https://example.com/cart/<redacted>');
  assert.equal(safeUrl('https://example.com/publications/book/?tracking=secret'), 'https://example.com/publications/book/');
});

test('missing security headers and obsolete script allowances produce actionable differences', () => {
  const rules = [
    { path: '/*', name: 'Content-Security-Policy', value: "script-src 'self' 'sha256-new'" },
    { path: '/*', name: 'Strict-Transport-Security', value: 'max-age=31536000' },
  ];
  const missing = headerMismatches(rules, '/', { 'content-security-policy': "script-src 'self' 'sha256-old'" });
  assert.equal(missing.length, 2);
  assert.equal(missing[1].actual, '<missing>');
  assert.equal(missing[0].expected, "script-src 'self' 'sha256-new'");
});

test('cache policy checks apply to matching assets and exclude other paths', () => {
  const rules = [{ path: '/assets/maplibre/*', name: 'Cache-Control', value: 'public, max-age=31536000, immutable' }];
  assert.equal(headerMismatches(rules, '/assets/maplibre/maplibre-gl.css', { 'cache-control': 'public, max-age=0' }).length, 1);
  assert.deepEqual(headerMismatches(rules, '/assets/maplibre/maplibre-gl.css', { 'cache-control': rules[0].value }), []);
  assert.deepEqual(headerMismatches(rules, '/', {}), []);
});
