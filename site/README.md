# Lid Awake Landing Page

Static site for `lidawake.pages.dev`. No build step: Cloudflare Pages serves this directory as-is, plus `functions/` as Pages Functions.

## Local preview

```bash
python3 -m http.server 4174 --directory site
```

Then open `http://localhost:4174`. The Cloudflare geo signal (`window.__LID_AWAKE_GEO__`) is not present outside Cloudflare, so language falls back to `navigator.language`.

## Tests

```bash
node --test site/tests/*.test.mjs
```

## Deployment

The Pages project (`lidawake`, account `ho@thuongtin.com`) is created and deployed via Wrangler direct upload, no Git connection:

```bash
cd site && wrangler pages deploy . --project-name=lidawake --branch=main
```

Run this from inside `site/` (not the repo root) so Wrangler finds `functions/` at the deploy root and bundles `_middleware.js` as a Pages Function. Running it from the repo root with `wrangler pages deploy site` silently skips the Function.

The live URL is `https://lidawake.pages.dev`, confirmed serving 200 with the geo script injected (`window.__LID_AWAKE_GEO__`) and the version badge/download links reflecting the latest GitHub release.

## Architecture notes

- `assets/lang-resolver.mjs` and `assets/release-select.mjs` are dependency-free ES modules with no DOM access, covered by `node --test`.
- `assets/i18n.js`, `assets/version.js`, and `assets/main.js` are thin DOM-glue layers, verified manually in a browser.
- `functions/_middleware.js` injects `window.__LID_AWAKE_GEO__` from `request.cf.country` using `HTMLRewriter`. It cannot be exercised outside Cloudflare's edge runtime; verify it structurally and confirm behavior after the first deploy.
