# Site header and checkout checks

Every push to `main` and pull request builds the site and checks its intended
headers, browser CSP behavior, and representative checkout paths. Main pushes
and manual runs also check the public production site. A failed GitHub Actions
run flags a problem and saves the expected/actual differences and screenshots.

The checks have no Render API key and do not deploy, change headers, or recover
releases. Keep the key local. Render's existing automatic deployments remain
in place. Update Render manually after relevant engine, script, or provider
changes, then rerun the check workflow. If a deployment is still in progress,
rerun after Render reports live.

`render.json` supplies the production origin and representative checkout
fixtures. Abqari uses the built `_site/_headers` as its expected policy; Blueprint extras
are retained.

Shopify and Folio tests use fresh anonymous sessions and stop at the secure
card-entry form. They never fill customer or payment details or submit orders.
Update fixtures intentionally when changing a product or purchase component.

No Actions secrets or activation variables are needed. Use **Run workflow**
on `main` to repeat production checks. The shared [check documentation](https://github.com/grantrayner/abqari/tree/f82877c43f3a0d010ecdd294f0ddccd932e0e08f/actions/render-static) explains coverage and evidence.
