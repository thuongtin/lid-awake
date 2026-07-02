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
