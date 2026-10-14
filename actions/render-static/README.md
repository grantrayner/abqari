# Render static-site deployment

This action is shared by the production Abqari and Jekyll repositories.
Pin consumers to its full commit SHA. Set `RENDER_API_KEY` as a repository
Actions secret; it is supplied only to the Render API steps, never to the
browser checks. The action runs on the production branch after the site's
existing build and validation steps.

`deploy/render.json` identifies the service, repository, production origin,
publish directory, header sources, and representative checkout fixtures.
Jekyll uses the `headers` block in `render.yaml`. Abqari overlays the built
`_site/_headers` onto that block, so the bundled engine and `config/site.yml`
determine current script hashes and feature permissions. A Blueprint may
still declare extra rules such as `X-Frame-Options`.

The action first checks service identity and snapshots the current headers
and live commit. It serves the built site locally with the desired headers,
checks for CSP violations and header mismatches, and exercises each configured
Shopify or Folio flow as far as its card-entry form. It never fills customer
details, payment details, or submits an order.

During deployment the previous CSP accepts both old and new script hashes
and origins. Once the exact commit is live, the final configured rules replace
the transitional rules and API readback must match. A conversion between
`unsafe-inline` and hashed scripts is rejected before deployment because
combining them does not preserve the old inline-script behavior.

Production checks repeat the header and checkout tests in fresh anonymous
browser contexts. A failure fails the workflow and restores the previous
live commit and header snapshot. Recovery refuses to overwrite a newer release
or header edits made outside the current deployment.

Artifacts include the header plan and readback, deployment identifiers,
test results, and screenshots. Checkout tokens are redacted from results.
Shopify test items are removed from their anonymous carts. Folio test checkouts
are left unpaid and expire under the application's normal retention rules.

Disable Render's independent autodeploy only after the new workflow has
successfully completed for the repository. GitHub Actions then owns deployment
ordering. Job concurrency must use `cancel-in-progress: false` so a newer push
does not interrupt a release while transitional headers are active.

## Checkout fixtures

Each Shopify fixture specifies its product page, product ID, expected cart
title, store checkout host, and whether the product button renders inline.
Each Folio fixture specifies its product page, exact Buy now link, expected
book title, and checkout origin. Update the fixture when intentionally changing
the representative product or purchase component.

Run `ruby actions/render-static/test/render_static_test.rb` for the deployment
regression tests. The dedicated action verification workflow also checks that
a browser-visible CSP failure prevents preflight from passing.
