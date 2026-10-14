# Render deployment

Every push to `main` builds and verifies the site, tests its intended response
headers and configured checkout flows, deploys that exact commit, synchronizes
Render, and verifies production. A failed production check triggers recovery
to the previous live revision and headers. No test submits a payment.

`render.json` identifies this service and its representative purchase flows.
The built `_site/_headers` is authoritative for Abqari rules; `config/site.yml`
controls features and the bundled engine generates script hashes. Any extra
Blueprint rules are retained.

After successful activation, disable Render automatic Git deploys; GitHub
Actions owns the release order. Set repository Actions variable `RENDER_SYNC_ENABLED=true` only after
configuring `RENDER_API_KEY` in repository Actions secrets. To rerun deployment, use the workflow's **Run workflow** button on
`main`. Review the deployment evidence artifact for headers, checkout results,
and screenshots. Intentional purchase component changes may need a fixture
update in `render.json`.

The shared action is pinned to an immutable commit. Its [documentation](https://github.com/grantrayner/abqari/tree/95b1fa7bdc3809bd3705544f13663a3c81d1f4a5/actions/render-static) describes validation and recovery.
