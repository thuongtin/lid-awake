import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { dict } from '../assets/i18n-dict.mjs';

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

test('every data-i18n key in index.html exists in both en and vi dictionaries', () => {
  const html = readFileSync(path.join(SITE_ROOT, 'index.html'), 'utf8');
  const keys = new Set([...html.matchAll(/data-i18n="([^"]+)"/g)].map((m) => m[1]));
  assert.ok(keys.size > 0, 'expected at least one data-i18n attribute in index.html');
  const missingFromEn = [...keys].filter((key) => !(key in dict.en));
  const missingFromVi = [...keys].filter((key) => !(key in dict.vi));
  assert.deepEqual(missingFromEn, []);
  assert.deepEqual(missingFromVi, []);
});
