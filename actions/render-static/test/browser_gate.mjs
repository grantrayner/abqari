import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const checker = resolve(dirname(fileURLToPath(import.meta.url)), '../checkout_checks.mjs');
const fixture = await mkdtemp(resolve(tmpdir(), 'render-browser-gate-'));
try {
  await mkdir(resolve(fixture, '_site'));
  await mkdir(resolve(fixture, 'deployment-evidence'));
  const script = 'document.body.dataset.loaded = "yes";';
  await writeFile(resolve(fixture, '_site/index.html'), `<html><body>Fixture<script>${script}</script></body></html>`);
  await writeFile(resolve(fixture, 'config.json'), JSON.stringify({ origin: 'https://fixture.example', publish_path: '_site', commerce_tests: [] }));
  const run = async policy => {
    await writeFile(resolve(fixture, 'deployment-evidence/plan.json'), JSON.stringify({ desired: [{ path: '/*', name: 'Content-Security-Policy', value: policy }] }));
    const result = spawnSync(process.execPath, [checker, 'local'], { cwd: fixture, env: { ...process.env, RENDER_DEPLOY_CONFIG: 'config.json' }, encoding: 'utf8', timeout: 120000 });
    const evidence = JSON.parse(await readFile(resolve(fixture, 'deployment-evidence/local-checks.json'), 'utf8'));
    return { status: result.status, evidence };
  };
  const blocked = await run("default-src 'self'; script-src 'self'");
  assert.equal(blocked.status, 1, 'Blocked inline script must fail the browser preflight');
  assert(blocked.evidence.failures.some(f => f.message.includes('CSP violations')));
  const hash = createHash('sha256').update(script).digest('base64');
  const allowed = await run(`default-src 'self'; script-src 'self' 'sha256-${hash}'`);
  assert.equal(allowed.status, 0, JSON.stringify(allowed.evidence));
  assert.equal(allowed.evidence.payments_submitted, false);
  console.log('Browser gate rejects a blocked script and accepts the matching hash');
} finally {
  await rm(fixture, { recursive: true, force: true });
}
