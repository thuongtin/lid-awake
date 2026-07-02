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
