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
