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
