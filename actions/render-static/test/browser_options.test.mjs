import test from 'node:test';
import assert from 'node:assert/strict';
import { browserOptions } from '../browser_options.mjs';

test('existing consumers keep the same bundled headless browser', () => {
  assert.deepEqual(browserOptions(), { headless: true });
  assert.deepEqual(browserOptions('chromium'), { headless: true });
});

test('Chrome is explicit and stays headless', () => {
  assert.deepEqual(browserOptions('chrome'), { headless: true, channel: 'chrome' });
});

test('unknown or malformed browser choices fail rather than bypassing checks', () => {
  for (const channel of ['', 'firefox', 'Chrome', 'chrome; true', '../chrome', null, {}]) {
    assert.throws(() => browserOptions(channel), /Unsupported browser-channel/);
  }
});
