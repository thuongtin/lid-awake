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
