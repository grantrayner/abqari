# Static-site header and checkout checks

This action checks the built site and its public production site. It has no
Render API client, API key input, deploy step, header update, or recovery step.
Keep the Render credential local. A failed check reports a problem; an operator
reviews and updates Render manually when needed.

`deploy/render.json` supplies the production origin, published build directory,
header sources, and representative checkout fixtures. Jekyll uses the headers
in `render.yaml`. Abqari's generated `_site/_headers` overlays that file, so
script hashes and feature permissions follow the bundled engine and site
configuration. Blueprint extras such as `X-Frame-Options` are retained.

The action serves the build with its intended headers and checks browser CSP
violations. On production it compares public HTTP response headers with the
expected rules, probes representative cache paths, and tests the homepage and
configured purchase pages. Grant Rayner also requires a fingerprinted font
stylesheet. Stronger platform HSTS is accepted; missing or weaker protection
fails. Rules whose paths have no built files are recorded as unprobed.
A failed workflow includes expected/actual differences, browser diagnostics,
and screenshots in its evidence artifact.

Shopify and Folio checks use fresh anonymous browser contexts and stop when
the correct checkout's secure card-entry frame is visible. They do not enter
customer or payment details or submit orders. Successful Shopify checks remove
their test items; unpaid Folio sessions expire under normal retention rules.
Checkout session identifiers are redacted from the evidence.

Site workflows run the build and local checks on pushes and pull requests.
Production checks run on `main` pushes and manual runs. A production check can
flag a deploy that is still in progress; rerun it after Render reports live.
Render's existing deployment settings are retained. If relevant source changes
require new CSP hashes or provider permissions, update the headers manually
and rerun the checks. Failed checks never change Render settings.

Consumers pin the action to a full commit SHA. GitHub tokens have only
`contents: read`; no Actions secrets are required. Source and fixtures are
public configuration, not credentials.

On a runner that already has Google Chrome (such as GitHub's Ubuntu x64
image), set `browser-channel: chrome` to reuse it and avoid browser downloads
and operating-system dependency installation. Both local and live checks,
including CSP enforcement and checkout flows, still run. Missing Chrome or
an unsupported channel fails the job. The default remains downloaded Chromium
for existing consumers and runners without Chrome.

Run the Ruby policy tests, Node policy tests, and browser gate self-test with:

```
bundle exec ruby actions/render-static/test/header_policy_test.rb
node --test actions/render-static/test/policy.test.mjs
node --test actions/render-static/test/browser_options.test.mjs
node actions/render-static/test/browser_gate.mjs
RENDER_CHECK_BROWSER=chrome node actions/render-static/test/browser_gate.mjs
```
