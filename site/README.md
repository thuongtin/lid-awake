# Lid Awake Landing Page

Static site for `lidawake.thuongtin.com`. No build step: Cloudflare Pages serves this directory as-is, plus `functions/` as Pages Functions.

## Local preview

```bash
python3 -m http.server 4174 --directory site
```

Then open `http://localhost:4174`. The Cloudflare geo signal (`window.__LID_AWAKE_GEO__`) is not present outside Cloudflare, so language falls back to `navigator.language`.

## Tests

```bash
node --test site/tests/*.test.mjs
```

## Deployment (manual, one-time, done by the Cloudflare account owner)

1. In the Cloudflare dashboard (account `ho@thuongtin.com`), create a Pages project connected to this GitHub repository, with root directory `site/` and no build command.
2. Add the custom domain `lidawake.thuongtin.com` to the Pages project and create the corresponding DNS record in the `thuongtin.com` zone.
3. After the first deploy, verify the page resolves the Cloudflare geo header correctly (Vietnamese copy for VN traffic) and that the version badge and download links reflect the latest GitHub release.

## Architecture notes

- `assets/lang-resolver.mjs` and `assets/release-select.mjs` are dependency-free ES modules with no DOM access, covered by `node --test`.
- `assets/i18n.js`, `assets/version.js`, and `assets/main.js` are thin DOM-glue layers, verified manually in a browser.
- `functions/_middleware.js` injects `window.__LID_AWAKE_GEO__` from `request.cf.country` using `HTMLRewriter`. It cannot be exercised outside Cloudflare's edge runtime; verify it structurally and confirm behavior after the first deploy.
