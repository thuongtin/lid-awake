import { dict } from './i18n-dict.mjs';

function copyToClipboard(text, button) {
  navigator.clipboard.writeText(text).then(() => {
    const original = button.textContent;
    const lang = document.documentElement.lang || 'en';
    button.textContent = dict[lang]['install.copied'] || 'Copied!';
    button.classList.add('copied');
    setTimeout(() => {
      button.textContent = original;
      button.classList.remove('copied');
    }, 1500);
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
