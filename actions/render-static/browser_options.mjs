import assert from 'node:assert/strict';

// Choosing the runner's installed Chrome avoids downloading another browser.
// Browser selection never changes the checks, and invalid inputs must fail.
export function browserOptions(channel = 'chromium') {
  assert(['chromium', 'chrome'].includes(channel), 'Unsupported browser-channel');
  return channel === 'chrome' ? { headless: true, channel: 'chrome' } : { headless: true };
}
