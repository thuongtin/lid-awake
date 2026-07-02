# Lid Awake Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a static, zero-build landing page at `site/` that reproduces the approved design, auto-detects the visitor's language (EN/VI) via Cloudflare edge geo with manual override, and auto-detects the latest GitHub release for the version badge and download links.

**Architecture:** Plain HTML/CSS/JS, no framework, no build step. Two pure-logic ES modules (`lang-resolver.mjs`, `release-select.mjs`) hold the testable decision logic; thin DOM-glue modules (`i18n.js`, `version.js`, `main.js`) wire that logic to `index.html`. A Cloudflare Pages Function (`functions/_middleware.js`) injects the edge geo signal server-side. Node's built-in test runner covers the pure logic and content-integrity checks (em dash guard, i18n key coverage); DOM/browser behavior is verified manually with the Preview tool.

**Tech Stack:** HTML5, CSS3 (custom properties), vanilla ES modules, Node.js built-in test runner (`node:test`, `node:assert/strict`), Cloudflare Pages Functions (`HTMLRewriter`).

## Global Constraints

- No em dash (—) anywhere in shipped copy, code comments, or docs (EN and VI equally). Use `,`, `:`, `.`, or `·`.
- No CMS, no build step, no JS framework.
- Claude does not create/configure the Cloudflare Pages project, DNS record, or custom domain. Document the manual steps only.
- Only English and Vietnamese are supported.
- Version badge and download links must degrade gracefully (keep static fallback) if the GitHub API call fails.
- Language resolution priority: `localStorage` override > `window.__LID_AWAKE_GEO__` (server-injected) > `navigator.language` > default `en`.

---

## File Structure

```
site/
  index.html                 # semantic markup, data-i18n attributes, script tags
  assets/
    style.css                # design tokens + all section styles, responsive
    lang-resolver.mjs        # pure: resolveLanguage({stored, geoCountry, navigatorLanguage}) -> 'en'|'vi'
    release-select.mjs       # pure: selectDownloadAsset, formatVersionLabel, findChecksumAssetName, isCacheFresh
    i18n-dict.mjs            # pure data: { en: {...}, vi: {...} } dictionary, keyed by data-i18n value
    i18n.js                  # DOM glue: applies language, wires EN/VI toggle, persists choice
    version.js                # DOM glue: fetches GitHub release, caches, updates DOM
    main.js                   # DOM glue: copy-to-clipboard buttons
  functions/
    _middleware.js            # Cloudflare Pages Function: injects __LID_AWAKE_GEO__
  tests/
    lang-resolver.test.mjs
    release-select.test.mjs
    content-integrity.test.mjs   # em dash guard + i18n key coverage, scans the whole site/ tree
  README.md                  # deployment steps for the Cloudflare Pages project (manual, for account owner)
```

**Interfaces produced by pure modules (used by DOM glue and tests):**

```js
// site/assets/lang-resolver.mjs
export function resolveLanguage({ stored, geoCountry, navigatorLanguage }) // -> 'en' | 'vi'

// site/assets/release-select.mjs
export function selectDownloadAsset(release)      // -> string (URL) | null
export function formatVersionLabel(release)       // -> string (e.g. "v0.1.2") | null
export function findChecksumAssetName(release)    // -> string (asset name) | null
export function isCacheFresh(cachedAt, now, maxAgeMs) // -> boolean

// site/assets/i18n-dict.mjs
export const dict // -> { en: Record<string,string>, vi: Record<string,string> }
```

Both `lang-resolver.mjs` and `release-select.mjs` are dependency-free ES modules loadable unmodified by both the browser (`<script type="module">`) and Node's test runner (`.mjs` extension forces ESM, no `package.json` needed).

---

## Task 1: Pure language-resolution logic

**Files:**
- Create: `site/assets/lang-resolver.mjs`
- Test: `site/tests/lang-resolver.test.mjs`

**Interfaces:**
- Produces: `resolveLanguage({ stored, geoCountry, navigatorLanguage })` as defined above.

- [ ] **Step 1: Write the failing test**

```js
// site/tests/lang-resolver.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveLanguage } from '../assets/lang-resolver.mjs';

test('stored preference always wins', () => {
  assert.equal(resolveLanguage({ stored: 'vi', geoCountry: 'US', navigatorLanguage: 'en-US' }), 'vi');
  assert.equal(resolveLanguage({ stored: 'en', geoCountry: 'VN', navigatorLanguage: 'vi-VN' }), 'en');
});

test('an invalid stored value is ignored', () => {
  assert.equal(resolveLanguage({ stored: 'fr', geoCountry: 'VN', navigatorLanguage: 'en-US' }), 'vi');
});

test('VN geo country maps to vi when no stored preference', () => {
  assert.equal(resolveLanguage({ stored: null, geoCountry: 'VN', navigatorLanguage: 'en-US' }), 'vi');
});

test('non VN geo country maps to en', () => {
  assert.equal(resolveLanguage({ stored: null, geoCountry: 'US', navigatorLanguage: 'vi-VN' }), 'en');
});

test('lowercase geo country is handled', () => {
  assert.equal(resolveLanguage({ stored: null, geoCountry: 'vn', navigatorLanguage: 'en-US' }), 'vi');
});

test('falls back to navigator.language when geo is absent', () => {
  assert.equal(resolveLanguage({ stored: null, geoCountry: null, navigatorLanguage: 'vi-VN' }), 'vi');
  assert.equal(resolveLanguage({ stored: null, geoCountry: null, navigatorLanguage: 'en-US' }), 'en');
});

test('defaults to en when nothing is available', () => {
  assert.equal(resolveLanguage({ stored: null, geoCountry: null, navigatorLanguage: null }), 'en');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test site/tests/lang-resolver.test.mjs`
Expected: FAIL (`Cannot find module '../assets/lang-resolver.mjs'`)

- [ ] **Step 3: Implement**

```js
// site/assets/lang-resolver.mjs
export function resolveLanguage({ stored, geoCountry, navigatorLanguage }) {
  if (stored === 'en' || stored === 'vi') {
    return stored;
  }
  if (typeof geoCountry === 'string' && geoCountry.length === 2) {
    return geoCountry.toUpperCase() === 'VN' ? 'vi' : 'en';
  }
  if (typeof navigatorLanguage === 'string' && navigatorLanguage.toLowerCase().startsWith('vi')) {
    return 'vi';
  }
  return 'en';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `node --test site/tests/lang-resolver.test.mjs`
Expected: PASS, 7/7 tests

- [ ] **Step 5: Commit**

```bash
git add site/assets/lang-resolver.mjs site/tests/lang-resolver.test.mjs
git commit -m "Add pure language-resolution logic for the landing page"
```

---

## Task 2: Pure GitHub release-selection logic

**Files:**
- Create: `site/assets/release-select.mjs`
- Test: `site/tests/release-select.test.mjs`

**Interfaces:**
- Produces: `selectDownloadAsset`, `formatVersionLabel`, `findChecksumAssetName`, `isCacheFresh` as defined above.

- [ ] **Step 1: Write the failing test**

```js
// site/tests/release-select.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  selectDownloadAsset,
  formatVersionLabel,
  findChecksumAssetName,
  isCacheFresh,
} from '../assets/release-select.mjs';

const sampleRelease = {
  tag_name: 'v0.1.2',
  assets: [
    { name: 'LidAwake-0.1.2-macos.dmg', browser_download_url: 'https://example.com/LidAwake-0.1.2-macos.dmg' },
    { name: 'LidAwake-0.1.2-macos.dmg.sha256', browser_download_url: 'https://example.com/LidAwake-0.1.2-macos.dmg.sha256' },
    { name: 'LidAwake-0.1.2-macos.zip', browser_download_url: 'https://example.com/LidAwake-0.1.2-macos.zip' },
  ],
};

test('selectDownloadAsset prefers the dmg asset', () => {
  assert.equal(selectDownloadAsset(sampleRelease), 'https://example.com/LidAwake-0.1.2-macos.dmg');
});

test('selectDownloadAsset falls back to zip when no dmg is present', () => {
  const release = { assets: [{ name: 'LidAwake-0.1.2-macos.zip', browser_download_url: 'https://example.com/zip' }] };
  assert.equal(selectDownloadAsset(release), 'https://example.com/zip');
});

test('selectDownloadAsset returns null when neither asset exists', () => {
  assert.equal(selectDownloadAsset({ assets: [] }), null);
  assert.equal(selectDownloadAsset(null), null);
});

test('formatVersionLabel returns the tag as-is when it already starts with v', () => {
  assert.equal(formatVersionLabel(sampleRelease), 'v0.1.2');
});

test('formatVersionLabel prefixes a bare version with v', () => {
  assert.equal(formatVersionLabel({ tag_name: '0.1.2' }), 'v0.1.2');
});

test('formatVersionLabel returns null when tag_name is missing', () => {
  assert.equal(formatVersionLabel({}), null);
  assert.equal(formatVersionLabel(null), null);
});

test('findChecksumAssetName finds the dmg sha256 file name', () => {
  assert.equal(findChecksumAssetName(sampleRelease), 'LidAwake-0.1.2-macos.dmg.sha256');
});

test('findChecksumAssetName returns null when absent', () => {
  assert.equal(findChecksumAssetName({ assets: [] }), null);
});

test('isCacheFresh compares age against a max age window', () => {
  assert.equal(isCacheFresh(1000, 1000 + 60_000, 3_600_000), true);
  assert.equal(isCacheFresh(1000, 1000 + 4_000_000, 3_600_000), false);
  assert.equal(isCacheFresh('not-a-number', 1000, 3_600_000), false);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test site/tests/release-select.test.mjs`
Expected: FAIL (`Cannot find module '../assets/release-select.mjs'`)

- [ ] **Step 3: Implement**

```js
// site/assets/release-select.mjs
export function selectDownloadAsset(release) {
  const assets = Array.isArray(release && release.assets) ? release.assets : [];
  const dmg = assets.find((asset) => asset.name && asset.name.endsWith('.dmg'));
  if (dmg) {
    return dmg.browser_download_url;
  }
  const zip = assets.find((asset) => asset.name && asset.name.endsWith('.zip'));
  return zip ? zip.browser_download_url : null;
}

export function formatVersionLabel(release) {
  if (!release || !release.tag_name) {
    return null;
  }
  return release.tag_name.startsWith('v') ? release.tag_name : `v${release.tag_name}`;
}

export function findChecksumAssetName(release) {
  const assets = Array.isArray(release && release.assets) ? release.assets : [];
  const shaAsset = assets.find((asset) => asset.name && asset.name.endsWith('.dmg.sha256'));
  return shaAsset ? shaAsset.name : null;
}

export function isCacheFresh(cachedAt, now, maxAgeMs) {
  if (typeof cachedAt !== 'number') {
    return false;
  }
  return now - cachedAt < maxAgeMs;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `node --test site/tests/release-select.test.mjs`
Expected: PASS, 9/9 tests

- [ ] **Step 5: Commit**

```bash
git add site/assets/release-select.mjs site/tests/release-select.test.mjs
git commit -m "Add pure GitHub release-selection logic for the landing page"
```

---

## Task 3: Content-integrity guard (em dash scan)

Written now, before any markup exists, so every later task is checked by it automatically (the test globs the whole `site/` tree at run time).

**Files:**
- Create: `site/tests/content-integrity.test.mjs`

- [ ] **Step 1: Write the test**

```js
// site/tests/content-integrity.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SITE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SCANNED_EXTENSIONS = new Set(['.html', '.css', '.js', '.mjs', '.md']);
const EM_DASH = String.fromCharCode(0x2014);

function collectFiles(dir) {
  const entries = readdirSync(dir);
  let files = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry);
    const stat = statSync(fullPath);
    if (stat.isDirectory()) {
      files = files.concat(collectFiles(fullPath));
    } else if (SCANNED_EXTENSIONS.has(path.extname(fullPath))) {
      files.push(fullPath);
    }
  }
  return files;
}

test('no em dash character anywhere under site/', () => {
  const files = collectFiles(SITE_ROOT);
  const offenders = [];
  for (const file of files) {
    const content = readFileSync(file, 'utf8');
    if (content.includes(EM_DASH)) {
      offenders.push(path.relative(SITE_ROOT, file));
    }
  }
  assert.deepEqual(offenders, []);
});
```

- [ ] **Step 2: Run the test to verify it passes on the currently empty tree**

Run: `node --test site/tests/content-integrity.test.mjs`
Expected: PASS, 1/1 test (nothing to scan yet besides the two files from Tasks 1-2, which contain no em dash)

- [ ] **Step 3: Commit**

```bash
git add site/tests/content-integrity.test.mjs
git commit -m "Add em dash content-integrity guard for the landing page"
```

---

## Task 4: i18n dictionary and i18n key-coverage test

**Files:**
- Create: `site/assets/i18n-dict.mjs`
- Modify: `site/tests/content-integrity.test.mjs` (add key-coverage test)

**Interfaces:**
- Consumes: nothing.
- Produces: `dict` (see File Structure interfaces above). Every `data-i18n` value used in Task 5's `index.html` must exist as a key in both `dict.en` and `dict.vi`.

- [ ] **Step 1: Write the dictionary**

```js
// site/assets/i18n-dict.mjs
export const dict = {
  en: {
    'nav.features': 'Features',
    'nav.how': 'How it works',
    'nav.specs': 'Specs',
    'nav.install': 'Install',
    'nav.github': 'GitHub',
    'nav.download': 'Download',

    'hero.badge': 'OPEN SOURCE · macOS 14+ · arm64',
    'hero.titleLine1': 'Keep your Mac working.',
    'hero.titleLine2': 'Even with the lid closed.',
    'hero.subtitle': 'Lid Awake holds off idle sleep while you work, and lets you keep going with the lid shut. You always have explicit, reversible control over what changes.',
    'hero.ctaDownload': 'Download for Mac',
    'hero.footnote': 'Free & open source · Notarized by Apple · No hidden sudo',

    'features.eyebrow': 'FEATURES',
    'features.heading': "Everything you need. Nothing you don't.",
    'features.item1.tag': 'IOPMAssertion',
    'features.item1.title': 'Keep awake, on demand',
    'features.item1.desc': 'Toggle it on in the menu bar. Pause for 30 minutes, an hour, or a custom time.',
    'features.item2.tag': 'Low Power aware',
    'features.item2.title': 'Battery-safe by default',
    'features.item2.desc': 'Set a battery cutoff, respect Low Power Mode, or hold awake only while plugged in.',
    'features.item3.tag': 'SMAppService',
    'features.item3.title': 'Closed-lid mode, opt-in',
    'features.item3.desc': 'Approve a signed helper once, then keep working with the lid shut. Turn it off just as easily.',
    'features.item4.tag': 'pmset display',
    'features.item4.title': 'Display on or off, your call',
    'features.item4.desc': 'Choose whether the screen stays lit or goes dark when the lid closes.',
    'features.item5.tag': 'CGSession',
    'features.item5.title': 'Lock on close, if you want it',
    'features.item5.desc': 'Ask macOS to lock the screen the moment the lid shuts.',
    'features.item6.tag': 'Sparkle 2 · EdDSA',
    'features.item6.title': 'Signed background updates',
    'features.item6.desc': 'Sparkle-powered update checks: signed, notarized, and checked right from the menu bar.',

    'how.eyebrow': 'HOW IT WORKS',
    'how.heading': 'Transparent limits, on purpose',
    'how.intro': "Lid Awake is explicit about what it changes on your Mac, and just as explicit about what it won't do.",
    'how.flowApp': 'Lid Awake.app',
    'how.flowAppSub': 'signed binary',
    'how.flowXpc': 'XPC · Team ID',
    'how.flowHelper': 'Lid Awake Helper',
    'how.flowHelperSub': 'LaunchDaemon',
    'how.flowApproved': 'approved',
    'how.flowPmset': 'pmset -a disablesleep',
    'how.flowPmsetSub': 'closed-lid mode',
    'how.note': 'macOS re-verifies the helper for the life of the connection (bundle ID, Apple anchor, and Team ID) via setCodeSigningRequirement. Nothing runs until you approve it in System Settings.',
    'how.doesHeading': 'What it does',
    'how.does1': 'Holds a standard macOS idle-sleep assertion while enabled.',
    'how.does2': 'Asks a macOS-approved helper to run the documented pmset -a disablesleep command, only once you approve it.',
    'how.does3': 'Restores normal sleep behavior the moment you disable, pause, or quit.',
    'how.does4': 'Releases every assertion automatically on low battery or Low Power Mode.',
    'how.doesntHeading': "What it won't do",
    'how.doesnt1': 'Never runs sudo from the app.',
    'how.doesnt2': 'Never installs a kernel extension or driver.',
    'how.doesnt3': "Never changes closed-lid behavior silently. Approval comes first.",
    'how.doesnt4': "Never claims a sleep state it didn't set.",
    'how.trustnote': "The privileged helper only accepts requests from Lid Awake's own signed binary, re-verified by Team ID for the life of the connection.",

    'specs.eyebrow': 'SPECS',
    'specs.heading': 'Under the hood',
    'specs.row1.label': 'PLATFORM',
    'specs.row1.value': 'macOS 14 or later',
    'specs.row2.label': 'ARCHITECTURE',
    'specs.row2.value': 'arm64 · Apple Silicon',
    'specs.row3.label': 'WAKE METHOD',
    'specs.row3.value': 'IOPMAssertion · PreventUserIdleSystemSleep',
    'specs.row4.label': 'CLOSED-LID',
    'specs.row4.value': 'pmset -a disablesleep (approved helper)',
    'specs.row5.label': 'HELPER',
    'specs.row5.value': 'LaunchDaemon · SMAppService · XPC',
    'specs.row6.label': 'UPDATES',
    'specs.row6.value': 'Sparkle 2 · signed appcast (EdDSA)',
    'specs.row7.label': 'DISTRIBUTION',
    'specs.row7.value': 'Developer ID · Notarized · DMG + zip · SHA-256',
    'specs.row8.label': 'LICENSE',
    'specs.row8.value': 'MIT',

    'install.eyebrow': 'INSTALL',
    'install.heading': 'Up and running in a minute',
    'install.homebrewLabel': 'Homebrew',
    'install.copy': 'Copy',
    'install.manualLabel': 'Manual download',
    'install.step1': 'Download the DMG and its .sha256 file from GitHub Releases.',
    'install.step2': 'Verify the checksum:',
    'install.step3': 'Open the DMG and drag Lid Awake to Applications.',
    'install.footnote': 'macOS 14 or later · Apple Silicon (arm64) only',

    'cta.heading': 'Stop babysitting your Mac.',
    'cta.subtitle': 'Free, open source, and built to stay out of your way.',
    'cta.download': 'Download for Mac',
    'cta.viewsource': 'View source',

    'footer.tagline': 'A native macOS menu bar utility.',
    'footer.badge': 'arm64 · macOS 14+',
    'footer.productLabel': 'Product',
    'footer.docsLabel': 'Docs',
    'footer.projectLabel': 'Project',
    'footer.docs1': 'Power Model',
    'footer.docs2': 'Developer Permissions',
    'footer.docs3': 'Releasing',
    'footer.docs4': 'Troubleshooting',
    'footer.project1': 'Changelog',
    'footer.project2': 'Security Policy',
    'footer.project3': 'Support',
    'footer.project4': 'License (MIT)',
    'footer.copyright': '© 2026 Lid Awake · MIT licensed.',
  },
  vi: {
    'nav.features': 'Tính năng',
    'nav.how': 'Cách hoạt động',
    'nav.specs': 'Thông số',
    'nav.install': 'Cài đặt',
    'nav.github': 'GitHub',
    'nav.download': 'Tải xuống',

    'hero.badge': 'MÃ NGUỒN MỞ · macOS 14+ · arm64',
    'hero.titleLine1': 'Giữ Mac của bạn luôn hoạt động.',
    'hero.titleLine2': 'Ngay cả khi đóng nắp máy.',
    'hero.subtitle': 'Lid Awake giữ máy không vào chế độ ngủ trong lúc bạn làm việc, và cho phép bạn tiếp tục làm việc ngay cả khi đóng nắp máy. Bạn luôn có toàn quyền kiểm soát rõ ràng và có thể hoàn tác đối với mọi thay đổi.',
    'hero.ctaDownload': 'Tải cho Mac',
    'hero.footnote': 'Miễn phí & mã nguồn mở · Được Apple notarize · Không có sudo ẩn',

    'features.eyebrow': 'TÍNH NĂNG',
    'features.heading': 'Mọi thứ bạn cần. Không gì thừa thãi.',
    'features.item1.tag': 'IOPMAssertion',
    'features.item1.title': 'Giữ máy thức, theo yêu cầu',
    'features.item1.desc': 'Bật nó lên ngay trên menu bar. Tạm dừng trong 30 phút, một giờ, hoặc một khoảng thời gian tùy chọn.',
    'features.item2.tag': 'Nhận biết Low Power',
    'features.item2.title': 'An toàn cho pin theo mặc định',
    'features.item2.desc': 'Đặt ngưỡng pin dừng lại, tôn trọng Low Power Mode, hoặc chỉ giữ thức khi đang cắm sạc.',
    'features.item3.tag': 'SMAppService',
    'features.item3.title': 'Chế độ đóng nắp máy, tùy chọn bật',
    'features.item3.desc': 'Phê duyệt một helper đã ký một lần, sau đó tiếp tục làm việc với nắp máy đóng. Tắt đi cũng dễ dàng như vậy.',
    'features.item4.tag': 'pmset display',
    'features.item4.title': 'Màn hình bật hay tắt, do bạn quyết định',
    'features.item4.desc': 'Chọn màn hình tiếp tục sáng hay tắt hẳn khi đóng nắp máy.',
    'features.item5.tag': 'CGSession',
    'features.item5.title': 'Khóa máy khi đóng nắp, nếu bạn muốn',
    'features.item5.desc': 'Yêu cầu macOS khóa màn hình ngay khi nắp máy đóng lại.',
    'features.item6.tag': 'Sparkle 2 · EdDSA',
    'features.item6.title': 'Cập nhật nền đã được ký',
    'features.item6.desc': 'Kiểm tra cập nhật bằng Sparkle: đã ký, đã notarize, và kiểm tra ngay trên menu bar.',

    'how.eyebrow': 'CÁCH HOẠT ĐỘNG',
    'how.heading': 'Giới hạn minh bạch, có chủ đích',
    'how.intro': 'Lid Awake nói rõ những gì nó thay đổi trên Mac của bạn, và cũng nói rõ không kém những gì nó sẽ không làm.',
    'how.flowApp': 'Lid Awake.app',
    'how.flowAppSub': 'tệp nhị phân đã ký',
    'how.flowXpc': 'XPC · Team ID',
    'how.flowHelper': 'Lid Awake Helper',
    'how.flowHelperSub': 'LaunchDaemon',
    'how.flowApproved': 'đã duyệt',
    'how.flowPmset': 'pmset -a disablesleep',
    'how.flowPmsetSub': 'chế độ đóng nắp',
    'how.note': 'macOS xác minh lại helper trong suốt vòng đời kết nối (bundle ID, Apple anchor, và Team ID) thông qua setCodeSigningRequirement. Không có gì chạy cho đến khi bạn phê duyệt trong System Settings.',
    'how.doesHeading': 'Những gì nó làm',
    'how.does1': 'Giữ một idle-sleep assertion chuẩn của macOS trong khi đang bật.',
    'how.does2': 'Yêu cầu một helper đã được macOS duyệt chạy lệnh pmset -a disablesleep đã được ghi rõ, chỉ sau khi bạn phê duyệt.',
    'how.does3': 'Khôi phục hành vi ngủ bình thường ngay khi bạn tắt, tạm dừng, hoặc thoát ứng dụng.',
    'how.does4': 'Tự động giải phóng mọi assertion khi pin yếu hoặc đang ở Low Power Mode.',
    'how.doesntHeading': 'Những gì nó không làm',
    'how.doesnt1': 'Không bao giờ chạy sudo từ ứng dụng.',
    'how.doesnt2': 'Không bao giờ cài kernel extension hay driver.',
    'how.doesnt3': 'Không bao giờ âm thầm thay đổi hành vi đóng nắp máy. Luôn cần phê duyệt trước.',
    'how.doesnt4': 'Không bao giờ báo cáo một trạng thái ngủ mà chính nó không thiết lập.',
    'how.trustnote': 'Helper đặc quyền chỉ chấp nhận yêu cầu từ chính tệp nhị phân đã ký của Lid Awake, được xác minh lại bằng Team ID trong suốt vòng đời kết nối.',

    'specs.eyebrow': 'THÔNG SỐ',
    'specs.heading': 'Bên trong ứng dụng',
    'specs.row1.label': 'NỀN TẢNG',
    'specs.row1.value': 'macOS 14 trở lên',
    'specs.row2.label': 'KIẾN TRÚC',
    'specs.row2.value': 'arm64 · Apple Silicon',
    'specs.row3.label': 'PHƯƠNG THỨC GIỮ THỨC',
    'specs.row3.value': 'IOPMAssertion · PreventUserIdleSystemSleep',
    'specs.row4.label': 'ĐÓNG NẮP MÁY',
    'specs.row4.value': 'pmset -a disablesleep (helper đã được duyệt)',
    'specs.row5.label': 'HELPER',
    'specs.row5.value': 'LaunchDaemon · SMAppService · XPC',
    'specs.row6.label': 'CẬP NHẬT',
    'specs.row6.value': 'Sparkle 2 · appcast đã ký (EdDSA)',
    'specs.row7.label': 'PHÂN PHỐI',
    'specs.row7.value': 'Developer ID · Đã notarize · DMG + zip · SHA-256',
    'specs.row8.label': 'GIẤY PHÉP',
    'specs.row8.value': 'MIT',

    'install.eyebrow': 'CÀI ĐẶT',
    'install.heading': 'Sẵn sàng chỉ trong một phút',
    'install.homebrewLabel': 'Homebrew',
    'install.copy': 'Sao chép',
    'install.manualLabel': 'Tải thủ công',
    'install.step1': 'Tải file DMG và file .sha256 tương ứng từ GitHub Releases.',
    'install.step2': 'Kiểm tra checksum:',
    'install.step3': 'Mở file DMG và kéo Lid Awake vào Applications.',
    'install.footnote': 'macOS 14 trở lên · Chỉ hỗ trợ Apple Silicon (arm64)',

    'cta.heading': 'Đừng canh chừng Mac của bạn nữa.',
    'cta.subtitle': 'Miễn phí, mã nguồn mở, và được xây dựng để không làm phiền bạn.',
    'cta.download': 'Tải cho Mac',
    'cta.viewsource': 'Xem mã nguồn',

    'footer.tagline': 'Một tiện ích menu bar macOS gốc.',
    'footer.badge': 'arm64 · macOS 14+',
    'footer.productLabel': 'Sản phẩm',
    'footer.docsLabel': 'Tài liệu',
    'footer.projectLabel': 'Dự án',
    'footer.docs1': 'Power Model',
    'footer.docs2': 'Quyền hạn nhà phát triển',
    'footer.docs3': 'Phát hành bản mới',
    'footer.docs4': 'Xử lý sự cố',
    'footer.project1': 'Nhật ký thay đổi',
    'footer.project2': 'Chính sách bảo mật',
    'footer.project3': 'Hỗ trợ',
    'footer.project4': 'Giấy phép (MIT)',
    'footer.copyright': '© 2026 Lid Awake · Giấy phép MIT.',
  },
};
```

- [ ] **Step 2: Add the key-coverage test to `content-integrity.test.mjs`**

Append to `site/tests/content-integrity.test.mjs` (after the existing `import` lines, add one more import; after the existing test, add a new test):

```js
import { dict } from '../assets/i18n-dict.mjs';
```

```js
test('every data-i18n key in index.html exists in both en and vi dictionaries', () => {
  const html = readFileSync(path.join(SITE_ROOT, 'index.html'), 'utf8');
  const keys = new Set([...html.matchAll(/data-i18n="([^"]+)"/g)].map((m) => m[1]));
  assert.ok(keys.size > 0, 'expected at least one data-i18n attribute in index.html');
  const missingFromEn = [...keys].filter((key) => !(key in dict.en));
  const missingFromVi = [...keys].filter((key) => !(key in dict.vi));
  assert.deepEqual(missingFromEn, []);
  assert.deepEqual(missingFromVi, []);
});
```

- [ ] **Step 3: Run the tests to verify the new test fails**

Run: `node --test site/tests/content-integrity.test.mjs`
Expected: FAIL (`site/index.html` does not exist yet, `readFileSync` throws ENOENT)

This is expected. `index.html` is built in Task 5. Leave the failure as-is; do not implement index.html here.

- [ ] **Step 4: Commit**

```bash
git add site/assets/i18n-dict.mjs site/tests/content-integrity.test.mjs
git commit -m "Add EN/VI dictionary and i18n key-coverage guard for the landing page"
```

---

## Task 5: index.html markup and style.css (full static page)

This is the largest task: it produces the visible page. Both `content-integrity.test.mjs` tests (em dash guard, key coverage) become the automated pass/fail gate; layout fidelity is checked manually via the Preview tool per this project's rule for frontend changes.

**Files:**
- Create: `site/index.html`
- Create: `site/assets/style.css`
- Create: `.claude/launch.json` entry `site-preview` (add alongside the existing `design-preview` entry)

**Interfaces:**
- Consumes: nothing directly (data-i18n keys must match Task 4's dictionary; class names referenced by later tasks: `.download-link`, `.lang-btn[data-lang]`, `.copy-btn[data-copy-target]`, `#version-badge`, `#shasum-command`).
- Produces: the DOM structure that `i18n.js`, `version.js`, and `main.js` attach to.

- [ ] **Step 1: Write `site/index.html`**

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Lid Awake: a native macOS wake utility for developers</title>
<meta name="description" content="Lid Awake keeps your Mac awake while you work, even with the lid closed. Free, open source, notarized by Apple.">
<link rel="canonical" href="https://lidawake.thuongtin.com/">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%230E0D0B'/%3E%3Ccircle cx='12' cy='16' r='5' fill='%23F0AE45'/%3E%3Ccircle cx='21' cy='16' r='5' fill='none' stroke='%23F0AE45' stroke-width='2'/%3E%3C/svg%3E">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&amp;family=JetBrains+Mono:wght@400;500;600&amp;display=swap" rel="stylesheet">
<link rel="stylesheet" href="./assets/style.css">
</head>
<body>
<header class="site-header">
  <div class="container header-inner">
    <a class="logo" href="#top">
      <span class="logo-mark" aria-hidden="true"></span>
      <span class="logo-text">Lid Awake</span>
      <span class="version-badge" id="version-badge">v0.1.2</span>
    </a>
    <nav class="site-nav" aria-label="Primary">
      <a href="#features" data-i18n="nav.features">Features</a>
      <a href="#how" data-i18n="nav.how">How it works</a>
      <a href="#specs" data-i18n="nav.specs">Specs</a>
      <a href="#install" data-i18n="nav.install">Install</a>
    </nav>
    <div class="header-actions">
      <a class="header-github" href="https://github.com/thuongtin/lid-awake" data-i18n="nav.github">GitHub</a>
      <div class="lang-toggle" role="group" aria-label="Language">
        <button type="button" class="lang-btn" data-lang="en">EN</button>
        <button type="button" class="lang-btn" data-lang="vi">VI</button>
      </div>
      <a class="btn btn-primary download-link" href="https://github.com/thuongtin/lid-awake/releases" data-i18n="nav.download">Download</a>
    </div>
  </div>
</header>

<main>
<section class="hero" id="top">
  <div class="container hero-inner">
    <div class="hero-copy">
      <p class="eyebrow" data-i18n="hero.badge">OPEN SOURCE · macOS 14+ · arm64</p>
      <h1 class="hero-title">
        <span data-i18n="hero.titleLine1">Keep your Mac working.</span><br>
        <span class="accent-text" data-i18n="hero.titleLine2">Even with the lid closed.</span>
      </h1>
      <p class="hero-subtitle" data-i18n="hero.subtitle">Lid Awake holds off idle sleep while you work, and lets you keep going with the lid shut. You always have explicit, reversible control over what changes.</p>
      <div class="hero-actions">
        <a class="btn btn-primary download-link" href="https://github.com/thuongtin/lid-awake/releases" data-i18n="hero.ctaDownload">Download for Mac</a>
        <code class="btn btn-secondary">brew install --cask lid-awake</code>
      </div>
      <p class="hero-footnote" data-i18n="hero.footnote">Free &amp; open source · Notarized by Apple · No hidden sudo</p>
    </div>
    <div class="hero-terminal" aria-hidden="true">
      <div class="terminal-chrome">
        <span class="dot dot-red"></span><span class="dot dot-yellow"></span><span class="dot dot-green"></span>
        <span class="terminal-title">lid-awake · zsh</span>
      </div>
      <pre class="terminal-body"><code>$ brew install --cask lid-awake
==&gt; Downloading lid-awake
==&gt; Installing Cask lid-awake
lid-awake was successfully installed.

$ pmset -g assertions | grep PreventUserIdle
PreventUserIdleSystemSleep 1</code></pre>
    </div>
  </div>
</section>

<section class="features" id="features">
  <div class="container">
    <p class="eyebrow" data-i18n="features.eyebrow">FEATURES</p>
    <h2 data-i18n="features.heading">Everything you need. Nothing you don't.</h2>
    <div class="features-grid">
      <article class="feature-card">
        <p class="feature-index">01</p>
        <p class="feature-tag" data-i18n="features.item1.tag">IOPMAssertion</p>
        <h3 data-i18n="features.item1.title">Keep awake, on demand</h3>
        <p data-i18n="features.item1.desc">Toggle it on in the menu bar. Pause for 30 minutes, an hour, or a custom time.</p>
      </article>
      <article class="feature-card">
        <p class="feature-index">02</p>
        <p class="feature-tag" data-i18n="features.item2.tag">Low Power aware</p>
        <h3 data-i18n="features.item2.title">Battery-safe by default</h3>
        <p data-i18n="features.item2.desc">Set a battery cutoff, respect Low Power Mode, or hold awake only while plugged in.</p>
      </article>
      <article class="feature-card">
        <p class="feature-index">03</p>
        <p class="feature-tag" data-i18n="features.item3.tag">SMAppService</p>
        <h3 data-i18n="features.item3.title">Closed-lid mode, opt-in</h3>
        <p data-i18n="features.item3.desc">Approve a signed helper once, then keep working with the lid shut. Turn it off just as easily.</p>
      </article>
      <article class="feature-card">
        <p class="feature-index">04</p>
        <p class="feature-tag" data-i18n="features.item4.tag">pmset display</p>
        <h3 data-i18n="features.item4.title">Display on or off, your call</h3>
        <p data-i18n="features.item4.desc">Choose whether the screen stays lit or goes dark when the lid closes.</p>
      </article>
      <article class="feature-card">
        <p class="feature-index">05</p>
        <p class="feature-tag" data-i18n="features.item5.tag">CGSession</p>
        <h3 data-i18n="features.item5.title">Lock on close, if you want it</h3>
        <p data-i18n="features.item5.desc">Ask macOS to lock the screen the moment the lid shuts.</p>
      </article>
      <article class="feature-card">
        <p class="feature-index">06</p>
        <p class="feature-tag" data-i18n="features.item6.tag">Sparkle 2 · EdDSA</p>
        <h3 data-i18n="features.item6.title">Signed background updates</h3>
        <p data-i18n="features.item6.desc">Sparkle-powered update checks: signed, notarized, and checked right from the menu bar.</p>
      </article>
    </div>
  </div>
</section>

<section class="how" id="how">
  <div class="container">
    <p class="eyebrow" data-i18n="how.eyebrow">HOW IT WORKS</p>
    <h2 data-i18n="how.heading">Transparent limits, on purpose</h2>
    <p class="how-intro" data-i18n="how.intro">Lid Awake is explicit about what it changes on your Mac, and just as explicit about what it won't do.</p>

    <div class="trust-flow">
      <div class="flow-node">
        <p class="flow-title" data-i18n="how.flowApp">Lid Awake.app</p>
        <p class="flow-sub" data-i18n="how.flowAppSub">signed binary</p>
      </div>
      <div class="flow-arrow"><span data-i18n="how.flowXpc">XPC · Team ID</span></div>
      <div class="flow-node">
        <p class="flow-title" data-i18n="how.flowHelper">Lid Awake Helper</p>
        <p class="flow-sub" data-i18n="how.flowHelperSub">LaunchDaemon</p>
      </div>
      <div class="flow-arrow"><span data-i18n="how.flowApproved">approved</span></div>
      <div class="flow-node">
        <p class="flow-title" data-i18n="how.flowPmset">pmset -a disablesleep</p>
        <p class="flow-sub" data-i18n="how.flowPmsetSub">closed-lid mode</p>
      </div>
    </div>
    <p class="flow-note" data-i18n="how.note">macOS re-verifies the helper for the life of the connection (bundle ID, Apple anchor, and Team ID) via setCodeSigningRequirement. Nothing runs until you approve it in System Settings.</p>

    <div class="does-grid">
      <div class="does-col">
        <h3 data-i18n="how.doesHeading">What it does</h3>
        <ul>
          <li data-i18n="how.does1">Holds a standard macOS idle-sleep assertion while enabled.</li>
          <li data-i18n="how.does2">Asks a macOS-approved helper to run the documented pmset -a disablesleep command, only once you approve it.</li>
          <li data-i18n="how.does3">Restores normal sleep behavior the moment you disable, pause, or quit.</li>
          <li data-i18n="how.does4">Releases every assertion automatically on low battery or Low Power Mode.</li>
        </ul>
      </div>
      <div class="doesnt-col">
        <h3 data-i18n="how.doesntHeading">What it won't do</h3>
        <ul>
          <li data-i18n="how.doesnt1">Never runs sudo from the app.</li>
          <li data-i18n="how.doesnt2">Never installs a kernel extension or driver.</li>
          <li data-i18n="how.doesnt3">Never changes closed-lid behavior silently. Approval comes first.</li>
          <li data-i18n="how.doesnt4">Never claims a sleep state it didn't set.</li>
        </ul>
      </div>
    </div>
    <p class="trust-note" data-i18n="how.trustnote">The privileged helper only accepts requests from Lid Awake's own signed binary, re-verified by Team ID for the life of the connection.</p>
  </div>
</section>

<section class="specs" id="specs">
  <div class="container">
    <p class="eyebrow" data-i18n="specs.eyebrow">SPECS</p>
    <h2 data-i18n="specs.heading">Under the hood</h2>
    <table class="specs-table">
      <tbody>
        <tr><td data-i18n="specs.row1.label">PLATFORM</td><td data-i18n="specs.row1.value">macOS 14 or later</td></tr>
        <tr><td data-i18n="specs.row2.label">ARCHITECTURE</td><td data-i18n="specs.row2.value">arm64 · Apple Silicon</td></tr>
        <tr><td data-i18n="specs.row3.label">WAKE METHOD</td><td data-i18n="specs.row3.value">IOPMAssertion · PreventUserIdleSystemSleep</td></tr>
        <tr><td data-i18n="specs.row4.label">CLOSED-LID</td><td data-i18n="specs.row4.value">pmset -a disablesleep (approved helper)</td></tr>
        <tr><td data-i18n="specs.row5.label">HELPER</td><td data-i18n="specs.row5.value">LaunchDaemon · SMAppService · XPC</td></tr>
        <tr><td data-i18n="specs.row6.label">UPDATES</td><td data-i18n="specs.row6.value">Sparkle 2 · signed appcast (EdDSA)</td></tr>
        <tr><td data-i18n="specs.row7.label">DISTRIBUTION</td><td data-i18n="specs.row7.value">Developer ID · Notarized · DMG + zip · SHA-256</td></tr>
        <tr><td data-i18n="specs.row8.label">LICENSE</td><td data-i18n="specs.row8.value">MIT</td></tr>
      </tbody>
    </table>
  </div>
</section>

<section class="install" id="install">
  <div class="container install-grid">
    <div class="install-card">
      <p class="eyebrow" data-i18n="install.eyebrow">INSTALL</p>
      <h2 data-i18n="install.heading">Up and running in a minute</h2>
      <div class="install-method">
        <p class="install-method-label" data-i18n="install.homebrewLabel">Homebrew</p>
        <div class="code-row">
          <code id="brew-command">brew tap thuongtin/tap &amp;&amp; brew install --cask lid-awake</code>
          <button type="button" class="copy-btn" data-copy-target="brew-command" data-i18n="install.copy">Copy</button>
        </div>
      </div>
      <div class="install-method">
        <p class="install-method-label" data-i18n="install.manualLabel">Manual download</p>
        <ol>
          <li data-i18n="install.step1">Download the DMG and its .sha256 file from GitHub Releases.</li>
          <li data-i18n="install.step2">Verify the checksum:</li>
        </ol>
        <div class="code-row">
          <code id="shasum-command">shasum -a 256 -c LidAwake-0.1.2-macos.dmg.sha256</code>
          <button type="button" class="copy-btn" data-copy-target="shasum-command" data-i18n="install.copy">Copy</button>
        </div>
        <ol start="3">
          <li data-i18n="install.step3">Open the DMG and drag Lid Awake to Applications.</li>
        </ol>
      </div>
      <p class="install-footnote" data-i18n="install.footnote">macOS 14 or later · Apple Silicon (arm64) only</p>
    </div>
  </div>
</section>

<section class="cta-banner">
  <div class="container">
    <h2 data-i18n="cta.heading">Stop babysitting your Mac.</h2>
    <p data-i18n="cta.subtitle">Free, open source, and built to stay out of your way.</p>
    <div class="cta-actions">
      <a class="btn btn-primary download-link" href="https://github.com/thuongtin/lid-awake/releases" data-i18n="cta.download">Download for Mac</a>
      <a class="btn btn-ghost" href="https://github.com/thuongtin/lid-awake" data-i18n="cta.viewsource">View source</a>
    </div>
  </div>
</section>
</main>

<footer class="site-footer">
  <div class="container footer-inner">
    <div class="footer-brand">
      <span class="logo-mark" aria-hidden="true"></span>
      <span class="logo-text">Lid Awake</span>
      <p data-i18n="footer.tagline">A native macOS menu bar utility.</p>
      <p class="footer-badge" data-i18n="footer.badge">arm64 · macOS 14+</p>
    </div>
    <div class="footer-col">
      <p class="footer-col-label" data-i18n="footer.productLabel">Product</p>
      <a href="#features" data-i18n="nav.features">Features</a>
      <a href="#specs" data-i18n="nav.specs">Specs</a>
      <a href="#install" data-i18n="nav.install">Install</a>
    </div>
    <div class="footer-col">
      <p class="footer-col-label" data-i18n="footer.docsLabel">Docs</p>
      <a href="https://github.com/thuongtin/lid-awake/blob/main/docs/power-model.md" data-i18n="footer.docs1">Power Model</a>
      <a href="https://github.com/thuongtin/lid-awake/blob/main/docs/developer-permissions.md" data-i18n="footer.docs2">Developer Permissions</a>
      <a href="https://github.com/thuongtin/lid-awake/blob/main/docs/releasing.md" data-i18n="footer.docs3">Releasing</a>
      <a href="https://github.com/thuongtin/lid-awake/blob/main/docs/troubleshooting.md" data-i18n="footer.docs4">Troubleshooting</a>
    </div>
    <div class="footer-col">
      <p class="footer-col-label" data-i18n="footer.projectLabel">Project</p>
      <a href="https://github.com/thuongtin/lid-awake/blob/main/CHANGELOG.md" data-i18n="footer.project1">Changelog</a>
      <a href="https://github.com/thuongtin/lid-awake/blob/main/SECURITY.md" data-i18n="footer.project2">Security Policy</a>
      <a href="https://github.com/thuongtin/lid-awake/blob/main/SUPPORT.md" data-i18n="footer.project3">Support</a>
      <a href="https://github.com/thuongtin/lid-awake/blob/main/LICENSE" data-i18n="footer.project4">License (MIT)</a>
    </div>
  </div>
  <div class="container footer-bottom">
    <p data-i18n="footer.copyright">© 2026 Lid Awake · MIT licensed.</p>
  </div>
</footer>

<script type="module" src="./assets/i18n.js"></script>
<script type="module" src="./assets/version.js"></script>
<script type="module" src="./assets/main.js"></script>
</body>
</html>
```

- [ ] **Step 2: Write `site/assets/style.css`**

```css
:root {
  --bg: #0E0D0B;
  --bg-raised: #13110B;
  --bg-panel: #0A0908;
  --fg: #F0EBE0;
  --fg-bright: #F5F1E8;
  --fg-muted: #9A9384;
  --fg-dim: #6A6456;
  --accent: #F0AE45;
  --accent-ink: #171208;
  --border: rgba(240, 235, 224, 0.08);
  --border-strong: rgba(240, 235, 224, 0.16);
  --font-sans: 'Space Grotesk', system-ui, sans-serif;
  --font-mono: 'JetBrains Mono', ui-monospace, monospace;
  --container-width: 1120px;
}

* { box-sizing: border-box; }

html { scroll-behavior: smooth; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font-family: var(--font-sans);
  font-size: 16px;
  line-height: 1.55;
}

h1, h2, h3 { color: var(--fg-bright); font-weight: 600; margin: 0 0 0.5em; }
h1 { font-size: clamp(2.25rem, 4vw, 3.25rem); line-height: 1.1; }
h2 { font-size: clamp(1.75rem, 3vw, 2.25rem); }
h3 { font-size: 1.125rem; }
p { margin: 0 0 1em; color: var(--fg); }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }

.container {
  max-width: var(--container-width);
  margin: 0 auto;
  padding: 0 24px;
}

section { padding: 88px 0; scroll-margin-top: 88px; }

.eyebrow {
  font-family: var(--font-mono);
  font-size: 0.75rem;
  letter-spacing: 0.12em;
  color: var(--fg-dim);
  margin-bottom: 0.75em;
}

.accent-text { color: var(--accent); }

.btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4em;
  padding: 0.75em 1.4em;
  border-radius: 8px;
  font-family: var(--font-mono);
  font-size: 0.9rem;
  font-weight: 500;
  border: 1px solid transparent;
  cursor: pointer;
}
.btn:hover { text-decoration: none; }
.btn-primary { background: var(--accent); color: var(--accent-ink); }
.btn-primary:hover { opacity: 0.9; }
.btn-secondary {
  background: var(--bg-panel);
  color: var(--fg-muted);
  border-color: var(--border-strong);
}
.btn-ghost { background: transparent; color: var(--fg); border-color: var(--border-strong); }

/* Header */
.site-header {
  position: sticky;
  top: 0;
  z-index: 10;
  background: rgba(14, 13, 11, 0.85);
  backdrop-filter: blur(8px);
  border-bottom: 1px solid var(--border);
}
.header-inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  height: 68px;
}
.logo { display: flex; align-items: center; gap: 10px; color: var(--fg-bright); }
.logo-mark {
  width: 22px;
  height: 22px;
  border-radius: 6px;
  background: linear-gradient(135deg, var(--accent), #b9791f);
  display: inline-block;
}
.logo-text { font-weight: 600; }
.version-badge {
  font-family: var(--font-mono);
  font-size: 0.7rem;
  color: var(--fg-dim);
  border: 1px solid var(--border-strong);
  border-radius: 999px;
  padding: 0.15em 0.6em;
}
.site-nav { display: flex; gap: 28px; font-size: 0.9rem; }
.site-nav a { color: var(--fg-muted); }
.site-nav a:hover { color: var(--fg-bright); }
.header-actions { display: flex; align-items: center; gap: 16px; }
.header-github { color: var(--fg-muted); font-size: 0.9rem; }
.lang-toggle {
  display: flex;
  border: 1px solid var(--border-strong);
  border-radius: 6px;
  overflow: hidden;
}
.lang-btn {
  font-family: var(--font-mono);
  font-size: 0.75rem;
  background: transparent;
  color: var(--fg-dim);
  border: none;
  padding: 0.4em 0.7em;
  cursor: pointer;
}
.lang-btn.active { background: var(--accent); color: var(--accent-ink); }

/* Hero */
.hero-inner {
  display: grid;
  grid-template-columns: 1.1fr 1fr;
  gap: 56px;
  align-items: center;
  padding-top: 40px;
}
.hero-title { margin-top: 0.3em; }
.hero-subtitle { color: var(--fg-muted); max-width: 46ch; }
.hero-actions { display: flex; gap: 14px; margin: 28px 0 18px; flex-wrap: wrap; }
.hero-footnote { font-family: var(--font-mono); font-size: 0.8rem; color: var(--fg-dim); }

.hero-terminal {
  background: var(--bg-panel);
  border: 1px solid var(--border-strong);
  border-radius: 12px;
  overflow: hidden;
}
.terminal-chrome {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 14px;
  border-bottom: 1px solid var(--border);
}
.dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
.dot-red { background: #e0605a; }
.dot-yellow { background: #e0b95a; }
.dot-green { background: #64c27b; }
.terminal-title { margin-left: 8px; font-family: var(--font-mono); font-size: 0.75rem; color: var(--fg-dim); }
.terminal-body {
  margin: 0;
  padding: 18px;
  font-family: var(--font-mono);
  font-size: 0.8rem;
  color: var(--fg-muted);
  overflow-x: auto;
}

/* Features */
.features { background: var(--bg-raised); }
.features-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 1px;
  background: var(--border);
  border: 1px solid var(--border);
  border-radius: 12px;
  overflow: hidden;
  margin-top: 32px;
}
.feature-card { background: var(--bg-raised); padding: 28px; }
.feature-index { font-family: var(--font-mono); font-size: 0.75rem; color: var(--fg-dim); margin-bottom: 1em; }
.feature-tag {
  display: inline-block;
  font-family: var(--font-mono);
  font-size: 0.7rem;
  color: var(--accent);
  border: 1px solid var(--border-strong);
  border-radius: 999px;
  padding: 0.2em 0.6em;
  margin-bottom: 0.8em;
}
.feature-card p:last-child { color: var(--fg-muted); margin-bottom: 0; }

/* How it works */
.how-intro { color: var(--fg-muted); max-width: 60ch; }
.trust-flow {
  display: flex;
  align-items: center;
  gap: 18px;
  flex-wrap: wrap;
  margin: 36px 0 20px;
}
.flow-node {
  background: var(--bg-raised);
  border: 1px solid var(--border-strong);
  border-radius: 10px;
  padding: 16px 20px;
}
.flow-title { font-family: var(--font-mono); font-size: 0.9rem; color: var(--fg-bright); margin: 0; }
.flow-sub { font-size: 0.75rem; color: var(--fg-dim); margin: 0.3em 0 0; }
.flow-arrow {
  font-family: var(--font-mono);
  font-size: 0.7rem;
  color: var(--fg-dim);
}
.flow-note { font-family: var(--font-mono); font-size: 0.8rem; color: var(--fg-dim); max-width: 70ch; }
.does-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 32px;
  margin-top: 32px;
}
.does-col ul, .doesnt-col ul { list-style: none; padding: 0; margin: 0; }
.does-col li, .doesnt-col li {
  padding: 12px 0;
  border-top: 1px solid var(--border);
  color: var(--fg-muted);
}
.trust-note { color: var(--fg-dim); font-size: 0.85rem; margin-top: 24px; max-width: 70ch; }

/* Specs */
.specs { background: var(--bg-raised); }
.specs-table { width: 100%; border-collapse: collapse; margin-top: 28px; }
.specs-table td {
  padding: 14px 0;
  border-top: 1px solid var(--border);
  font-family: var(--font-mono);
  font-size: 0.85rem;
}
.specs-table td:first-child { color: var(--fg-dim); width: 220px; }
.specs-table td:last-child { color: var(--fg); }

/* Install */
.install-card {
  background: var(--bg-panel);
  border: 1px solid var(--border-strong);
  border-radius: 12px;
  padding: 40px;
}
.install-method { margin-top: 28px; }
.install-method-label { font-weight: 600; color: var(--fg-bright); }
.code-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 10px 14px;
  margin-top: 8px;
}
.code-row code { font-family: var(--font-mono); font-size: 0.8rem; color: var(--fg-muted); overflow-x: auto; }
.copy-btn {
  font-family: var(--font-mono);
  font-size: 0.7rem;
  background: transparent;
  border: 1px solid var(--border-strong);
  color: var(--fg-dim);
  border-radius: 6px;
  padding: 0.35em 0.7em;
  cursor: pointer;
  flex-shrink: 0;
}
.copy-btn:hover { color: var(--fg-bright); border-color: var(--fg-dim); }
.install-card ol { color: var(--fg-muted); padding-left: 1.2em; }
.install-footnote { font-family: var(--font-mono); font-size: 0.75rem; color: var(--fg-dim); margin-top: 24px; }

/* CTA banner */
.cta-banner {
  background: var(--bg-panel);
  text-align: center;
}
.cta-banner p { color: var(--fg-muted); max-width: 50ch; margin: 0 auto 1.5em; }
.cta-actions { display: flex; gap: 14px; justify-content: center; flex-wrap: wrap; }

/* Footer */
.site-footer { background: var(--bg-panel); border-top: 1px solid var(--border); padding: 64px 0 0; }
.footer-inner {
  display: grid;
  grid-template-columns: 1.4fr 1fr 1fr 1fr;
  gap: 32px;
  padding-bottom: 48px;
}
.footer-brand p { color: var(--fg-muted); margin: 0.8em 0; }
.footer-badge { font-family: var(--font-mono); font-size: 0.7rem; color: var(--fg-dim); }
.footer-col-label {
  font-family: var(--font-mono);
  font-size: 0.7rem;
  letter-spacing: 0.08em;
  color: var(--fg-dim);
  margin-bottom: 1em;
}
.footer-col a { display: block; color: var(--fg-muted); font-size: 0.9rem; margin-bottom: 0.7em; }
.footer-col a:hover { color: var(--fg-bright); }
.footer-bottom {
  border-top: 1px solid var(--border);
  padding: 20px 0;
  color: var(--fg-dim);
  font-size: 0.8rem;
}

@media (max-width: 900px) {
  .hero-inner { grid-template-columns: 1fr; }
  .features-grid { grid-template-columns: repeat(2, 1fr); }
  .does-grid { grid-template-columns: 1fr; }
  .footer-inner { grid-template-columns: 1fr 1fr; }
}

@media (max-width: 640px) {
  .site-nav { display: none; }
  .features-grid { grid-template-columns: 1fr; }
  .footer-inner { grid-template-columns: 1fr; }
  section { padding: 56px 0; }
}
```

- [ ] **Step 3: Add a `site-preview` launch config alongside the existing `design-preview` entry**

Read the current `.claude/launch.json`, then edit it to this:

```json
{
  "version": "0.0.1",
  "configurations": [
    {
      "name": "design-preview",
      "runtimeExecutable": "python3",
      "runtimeArgs": [
        "-m",
        "http.server",
        "4173",
        "--directory",
        "/private/tmp/claude-501/-Users-ethan-Documents-Codex-2026-06-24-test-android-apps-android-emulator-qa/e8dbb6b2-077e-40ff-a242-3d965a052cfe/scratchpad/design-preview"
      ],
      "port": 4173
    },
    {
      "name": "site-preview",
      "runtimeExecutable": "python3",
      "runtimeArgs": ["-m", "http.server", "4174", "--directory", "site"],
      "port": 4174
    }
  ]
}
```

- [ ] **Step 4: Run the automated content-integrity tests**

Run: `node --test site/tests/content-integrity.test.mjs`
Expected: PASS, 2/2 tests (em dash guard and key-coverage test both pass now that `index.html` exists)

- [ ] **Step 5: Manual visual check via the Preview tool**

Start the `site-preview` server, take a screenshot at desktop width (1280) and mobile width (375), and confirm: dark background with amber accent renders, all 7 sections are present in order (header, hero, features, how it works, specs, install, CTA banner, footer), the terminal mockup and feature grid are readable, no layout overflow at either width.

- [ ] **Step 6: Commit**

```bash
git add site/index.html site/assets/style.css .claude/launch.json
git commit -m "Add landing page markup and stylesheet"
```

---

## Task 6: i18n.js DOM glue

**Files:**
- Create: `site/assets/i18n.js`

**Interfaces:**
- Consumes: `resolveLanguage` (Task 1), `dict` (Task 4), `window.__LID_AWAKE_GEO__` (set by Task 9's `_middleware.js`, absent on local preview).
- Produces: sets `document.documentElement.lang`, applies `dict[lang]` to every `[data-i18n]` element, highlights the active `.lang-btn`, persists the choice to `localStorage` key `lidawake-lang` on toggle click.

- [ ] **Step 1: Write `site/assets/i18n.js`**

```js
import { resolveLanguage } from './lang-resolver.mjs';
import { dict } from './i18n-dict.mjs';

const STORAGE_KEY = 'lidawake-lang';

function applyLanguage(lang) {
  document.documentElement.lang = lang;
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.getAttribute('data-i18n');
    const value = dict[lang][key];
    if (value !== undefined) {
      el.textContent = value;
    }
  });
  document.querySelectorAll('.lang-btn').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.lang === lang);
  });
}

function setLanguage(lang) {
  localStorage.setItem(STORAGE_KEY, lang);
  applyLanguage(lang);
}

function init() {
  const stored = localStorage.getItem(STORAGE_KEY);
  const geoCountry = window.__LID_AWAKE_GEO__ || null;
  const navigatorLanguage = navigator.language || null;
  const lang = resolveLanguage({ stored, geoCountry, navigatorLanguage });
  applyLanguage(lang);

  document.querySelectorAll('.lang-btn').forEach((btn) => {
    btn.addEventListener('click', () => setLanguage(btn.dataset.lang));
  });
}

init();
```

- [ ] **Step 2: Manual browser check via the Preview tool**

With the `site-preview` server running, reload the page and confirm the EN button is active by default (no geo signal locally, `navigator.language` is typically `en-US` in the preview browser). Click the VI button; confirm every visible string switches to the Vietnamese copy, `document.documentElement.lang` becomes `"vi"`, and the VI button gets the `active` class. Reload the page; confirm the VI choice persists (localStorage). Click EN to switch back.

- [ ] **Step 3: Commit**

```bash
git add site/assets/i18n.js
git commit -m "Wire EN/VI language resolution and toggle into the landing page"
```

---

## Task 7: version.js DOM glue

**Files:**
- Create: `site/assets/version.js`

**Interfaces:**
- Consumes: `selectDownloadAsset`, `formatVersionLabel`, `findChecksumAssetName`, `isCacheFresh` (Task 2).
- Produces: updates `#version-badge` textContent, every `.download-link` href, and `#shasum-command` textContent.

- [ ] **Step 1: Write `site/assets/version.js`**

```js
import {
  selectDownloadAsset,
  formatVersionLabel,
  findChecksumAssetName,
  isCacheFresh,
} from './release-select.mjs';

const CACHE_KEY = 'lidawake-release-cache';
const CACHE_MAX_AGE_MS = 60 * 60 * 1000;
const RELEASES_API_URL = 'https://api.github.com/repos/thuongtin/lid-awake/releases/latest';

function applyRelease(release) {
  const versionLabel = formatVersionLabel(release);
  const downloadUrl = selectDownloadAsset(release);
  const checksumAssetName = findChecksumAssetName(release);

  if (versionLabel) {
    const badge = document.getElementById('version-badge');
    if (badge) {
      badge.textContent = versionLabel;
    }
  }
  if (downloadUrl) {
    document.querySelectorAll('.download-link').forEach((link) => {
      link.href = downloadUrl;
    });
  }
  if (checksumAssetName) {
    const shasumEl = document.getElementById('shasum-command');
    if (shasumEl) {
      shasumEl.textContent = `shasum -a 256 -c ${checksumAssetName}`;
    }
  }
}

function readCache() {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function writeCache(release) {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify({ release, cachedAt: Date.now() }));
  } catch {
    /* localStorage unavailable; skip caching */
  }
}

async function init() {
  const cached = readCache();
  if (cached && isCacheFresh(cached.cachedAt, Date.now(), CACHE_MAX_AGE_MS)) {
    applyRelease(cached.release);
    return;
  }
  try {
    const response = await fetch(RELEASES_API_URL);
    if (!response.ok) {
      throw new Error(`GitHub API responded with ${response.status}`);
    }
    const release = await response.json();
    applyRelease(release);
    writeCache(release);
  } catch (error) {
    if (cached) {
      applyRelease(cached.release);
    }
    console.warn('Lid Awake: could not fetch the latest release, keeping static links.', error);
  }
}

init();
```

- [ ] **Step 2: Manual browser check via the Preview tool (success path)**

Reload the page with the `site-preview` server running and the network connected. Use `preview_network` to confirm a request to `api.github.com/repos/thuongtin/lid-awake/releases/latest` fires and returns 200. Confirm `#version-badge` shows the real latest tag, every `.download-link` href points at a `.dmg` `browser_download_url`, and `#shasum-command` shows the real `.dmg.sha256` file name.

- [ ] **Step 3: Manual browser check via the Preview tool (failure path)**

Use `preview_eval` to temporarily monkey-patch `window.fetch` to reject (e.g. `window.fetch = () => Promise.reject(new Error('offline'))`), clear `localStorage.lidawake-release-cache`, and reload. Confirm the page still renders with the static fallback `href="https://github.com/thuongtin/lid-awake/releases"` links, the static `v0.1.2` badge, and a `console.warn` (not an uncaught error) in `preview_console_logs`.

- [ ] **Step 4: Commit**

```bash
git add site/assets/version.js
git commit -m "Wire GitHub release auto-detection into the landing page"
```

---

## Task 8: main.js (copy-to-clipboard)

**Files:**
- Create: `site/assets/main.js`

- [ ] **Step 1: Write `site/assets/main.js`**

```js
function copyToClipboard(text, button) {
  navigator.clipboard.writeText(text).then(() => {
    const original = button.textContent;
    button.textContent = button.dataset.i18n === 'install.copy' ? original : original;
    button.classList.add('copied');
    setTimeout(() => button.classList.remove('copied'), 1500);
  }).catch((error) => {
    console.warn('Lid Awake: clipboard write failed.', error);
  });
}

document.querySelectorAll('.copy-btn[data-copy-target]').forEach((button) => {
  button.addEventListener('click', () => {
    const target = document.getElementById(button.dataset.copyTarget);
    if (target) {
      copyToClipboard(target.textContent, button);
    }
  });
});
```

- [ ] **Step 2: Manual browser check via the Preview tool**

Click each copy button; confirm (via `preview_eval` reading `navigator.clipboard` state or the `.copied` class briefly appearing) that the click handler runs without console errors.

- [ ] **Step 3: Commit**

```bash
git add site/assets/main.js
git commit -m "Add copy-to-clipboard interaction to the landing page"
```

---

## Task 9: Cloudflare Pages Function for geo injection

**Files:**
- Create: `site/functions/_middleware.js`

- [ ] **Step 1: Write `site/functions/_middleware.js`**

```js
export async function onRequest(context) {
  const response = await context.next();
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('text/html')) {
    return response;
  }

  const country = (context.request.cf && context.request.cf.country) || 'XX';
  const rewriter = new HTMLRewriter().on('head', {
    element(element) {
      element.append(`<script>window.__LID_AWAKE_GEO__="${country}";</script>`, { html: true });
    },
  });

  return rewriter.transform(response);
}
```

- [ ] **Step 2: Structural manual review (no automated test, per the design spec)**

Confirm by reading the file: `context.next()` is called first so the origin response is fetched before rewriting; the HTML content-type guard prevents rewriting non-HTML Pages Function responses (e.g. static assets served through the same middleware); the country fallback is `"XX"`, which `resolveLanguage` treats as non-VN and therefore resolves to English; the injected script tag matches exactly what `i18n.js` reads (`window.__LID_AWAKE_GEO__`). Note in the commit message that this cannot be exercised locally without Cloudflare's edge runtime and must be confirmed by the account owner after deploy, per the design spec's testing plan.

- [ ] **Step 3: Commit**

```bash
git add site/functions/_middleware.js
git commit -m "Add Cloudflare Pages Function to inject edge geo signal"
```

---

## Task 10: Deployment docs and final verification pass

**Files:**
- Create: `site/README.md`
- Modify: `README.md:5` (add a Website line under the bundle identifier line)

**Interfaces:**
- Consumes: nothing.

- [ ] **Step 1: Write `site/README.md`**

```markdown
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
```

- [ ] **Step 2: Add a Website line to the root `README.md`**

In `README.md`, change:

```markdown
Bundle identifier: `com.thuongtin.LidAwake`.
```

to:

```markdown
Bundle identifier: `com.thuongtin.LidAwake`.

Website: [lidawake.thuongtin.com](https://lidawake.thuongtin.com).
```

- [ ] **Step 3: Run the full test suite**

Run: `node --test site/tests/*.test.mjs`
Expected: PASS, all tests across `lang-resolver.test.mjs`, `release-select.test.mjs`, and `content-integrity.test.mjs`

- [ ] **Step 4: Final manual visual pass via the Preview tool**

At desktop (1280px) and mobile (375px) widths: scroll the full page, confirm every section renders without overflow, confirm the EN/VI toggle and version/download auto-detection still work end to end together (not just in isolation from earlier tasks), confirm `preview_console_logs` shows no uncaught errors.

- [ ] **Step 5: Grep the tree for the em dash character as a final human-readable confirmation (mirrors the automated test)**

Run: `grep -rn $'—' site/ || echo "no em dash found"`
Expected: `no em dash found`

- [ ] **Step 6: Commit**

```bash
git add site/README.md README.md
git commit -m "Add landing page deployment docs and link it from the project README"
```

---

## Self-Review

**Spec coverage:** Visual design and section order (Task 5), language auto-detection with the exact 3-tier priority and `_middleware.js` mechanism (Tasks 1, 6, 9), version auto-detection with the exact GitHub API URL, cache TTL, and DOM update targets (Tasks 2, 7), no em dash anywhere (Task 3 guard, run automatically by every later task), no CMS/build step/framework (plain HTML/CSS/JS throughout), Claude does not touch Cloudflare project/DNS/domain (Task 10 documents manual steps only), deployment doc (Task 10), testing plan's six checks (local static preview visual check: Task 5 Step 5 and Task 10 Step 4; EN/VI toggle check: Task 6 Step 2; version auto-detection check: Task 7 Step 2; fetch-failure fallback check: Task 7 Step 3; em dash grep: Task 3 automated + Task 10 Step 5 manual; `_middleware.js` structural review: Task 9 Step 2).

**Placeholder scan:** No `TBD`/`TODO` remain; every code step above is complete, runnable code.

**Type consistency:** `resolveLanguage`, `selectDownloadAsset`, `formatVersionLabel`, `findChecksumAssetName`, and `isCacheFresh` are used with the same names and argument shapes in their defining task, their tests, and their consuming DOM-glue task.
