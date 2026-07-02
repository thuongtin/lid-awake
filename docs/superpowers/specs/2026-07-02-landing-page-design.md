# Lid Awake Landing Page: Design

## Goal

Ship a marketing landing page for Lid Awake that:

1. Reproduces the approved "Lid Awake Landing Tech" design (dark theme, amber accent).
2. Auto-detects and shows the latest published version and a direct download link, without a manual content edit per release.
3. Auto-selects English or Vietnamese copy based on the visitor's geographic location, with a manual override the visitor can change at any time.
4. Contains no em dash (—) anywhere in the shipped copy, per the project's typography rule.

## Non-goals

- No CMS, no build step, no JS framework. Plain HTML/CSS/JS, matching the complexity of a single static page.
- No blog, no docs rendering, no contact form.
- Claude does not create or configure the Cloudflare Pages project, DNS record, or custom domain. Those are manual steps the account owner performs; this spec documents what to configure.
- No support for languages beyond English and Vietnamese.

## Hosting and domain

- Platform: Cloudflare Pages.
- Cloudflare account: `ho@thuongtin.com`.
- Custom domain: `lidawake.thuongtin.com`.
- Repo layout: Pages project root directory is `site/` inside this repository (monorepo-style, same pattern as `docs/`, `scripts/`, `script/`).
- No build command; Pages serves `site/` as static output and `site/functions/` as Pages Functions.

## File layout

```
site/
  index.html
  assets/
    style.css
    i18n.js
    version.js
    main.js
  functions/
    _middleware.js
  README.md          # deployment steps for the Cloudflare Pages project
```

## Visual design

Extracted from the approved design file (`Lid Awake Landing Tech.dc.html`) by rendering it and reading computed inline styles. Reimplemented as clean semantic HTML with an external stylesheet (CSS custom properties for the palette), not copied verbatim (the source file is design-tool output with non-semantic wrapper markup).

Palette:

| Token | Value | Use |
|---|---|---|
| `--bg` | `#0E0D0B` | Page background |
| `--bg-raised` | `#13110B` | Section/card background |
| `--bg-panel` | `#0A0908` | Footer, terminal panel background |
| `--fg` | `#F0EBE0` | Primary text |
| `--fg-bright` | `#F5F1E8` | Headings |
| `--fg-muted` | `#9A9384` | Secondary text |
| `--fg-dim` | `#6A6456` | Tertiary text, meta labels |
| `--accent` | `#F0AE45` | Amber accent, links, primary CTA |
| `--accent-ink` | `#171208` | Text on amber background |
| `--border` | `rgba(240,235,224,0.08-0.16)` | Borders (opacity varies by context) |

Fonts: `Space Grotesk` for headings and body copy, `JetBrains Mono` for nav, badges, code, and labels. Load both from a self-hosted `@font-face` (woff2) or Google Fonts `<link>`; final call made during implementation based on what keeps the page fast.

Sections, in order: sticky header (logo, version badge, nav, EN/VI toggle, Download CTA), hero (headline, subhead, dual CTA, terminal mockup), Features (6-card grid), How it works (trust flow diagram + does/doesn't lists), Specs (key-value table), Install (Homebrew card + manual download steps), closing CTA banner, footer (product/docs/project link columns).

## Language auto-detection (EN / VI)

Priority order, evaluated once on page load:

1. `localStorage.getItem('lidawake-lang')` — set the moment a visitor clicks the EN/VI toggle. Always wins once set.
2. `window.__LID_AWAKE_GEO__` — a country code injected server-side by `site/functions/_middleware.js`, which reads `request.cf.country` (Cloudflare's edge geo signal, no external API call, no extra network request). `VN` maps to Vietnamese; anything else maps to English.
3. `navigator.language` — fallback used only when `__LID_AWAKE_GEO__` is absent (e.g. local file preview, or a host that isn't Cloudflare). `vi*` maps to Vietnamese; anything else maps to English.

Implementation:

- `_middleware.js` calls `context.next()`, then uses `HTMLRewriter` to inject `<script>window.__LID_AWAKE_GEO__="XX";</script>` just before `</head>` of the HTML response, where `XX` is `context.request.cf.country` (falls back to `"XX"` if the field is unavailable, which resolves to English downstream).
- All translatable text in `index.html` carries a `data-i18n="key"` attribute (or `data-i18n-html` where the source has inline markup like `<br>`).
- `assets/i18n.js` holds an `en` / `vi` dictionary keyed the same way, applies the resolved language on load, updates `document.documentElement.lang`, and wires the EN/VI toggle buttons to switch language and persist the choice.
- Copy: Vietnamese translation written in natural tiếng Việt có dấu, technical terms kept in English (API, XPC, LaunchDaemon, Sparkle, IOPMAssertion, etc.), following the same tone as the existing English copy.

## Version auto-detection

- On load, `assets/version.js` fetches `https://api.github.com/repos/thuongtin/lid-awake/releases/latest` (public, unauthenticated, CORS-enabled for GET on public repos).
- Cache the parsed result in `localStorage` with a timestamp; reuse the cache for up to 1 hour before refetching, to stay well under GitHub's 60 requests/hour unauthenticated rate limit.
- On a successful response, update in place:
  - Header version badge text (currently static `v0.1.1`) → `release.tag_name`.
  - `href` of every "Download for Mac" link (currently `https://github.com/thuongtin/lid-awake/releases`) → the `browser_download_url` of the `.dmg` asset in `release.assets`.
  - The version placeholder in the manual-download `shasum -a 256 -c LidAwake-<version>-macos.dmg.sha256` snippet → the real filename.
- On fetch failure, timeout, or rate limit: catch the error, leave the existing static `/releases` links and generic copy untouched. The page must never show a broken state because of this.

## Copy and typography

- Every string in `index.html` and the `en`/`vi` dictionaries is free of the em dash (—). Existing em dashes in the source design are rewritten using a comma, colon, period, or the middle dot (`·`) already used elsewhere in the design, whichever reads most naturally in context.
- This applies to English and Vietnamese text equally.

## Deployment (manual steps, documented in `site/README.md`, not performed by Claude)

1. In Cloudflare dashboard (account `ho@thuongtin.com`), create a Pages project connected to this GitHub repo, root directory `site/`, no build command.
2. Add custom domain `lidawake.thuongtin.com` to the Pages project and create the corresponding DNS record in the `thuongtin.com` zone.
3. Verify the deployed page resolves the Cloudflare geo header correctly (Vietnamese for VN traffic) and that the version badge/download link reflect the latest GitHub release.

## Testing / verification plan

- Local static preview (via the existing `Claude_Preview` static file server pattern) to visually check layout against the approved design at desktop and mobile widths.
- Manual check of the EN/VI toggle: click switches all visible copy, persists across reload (localStorage), and `document.documentElement.lang` updates.
- Manual check of version auto-detection against the real GitHub API response (`api.github.com/repos/thuongtin/lid-awake/releases/latest`) in the browser console: badge and download href update correctly.
- Simulate a fetch failure (offline / blocked request) and confirm the page still renders with the static fallback links, no console-breaking error.
- Grep the final `site/` tree for the em dash character to confirm none remain.
- `_middleware.js` geo injection cannot be fully exercised outside Cloudflare's edge; verified structurally (correct `HTMLRewriter` usage, correct fallback) and left for the account owner to confirm post-deploy.
