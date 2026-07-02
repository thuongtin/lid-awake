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
