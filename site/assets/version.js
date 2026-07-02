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
