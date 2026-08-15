// Single source of truth for building the public customer QR-menu URL.
// Never hardcode localhost/127.0.0.1/private IPs here — the value always
// comes from an environment variable so it's correct in every deployment.
function publicMenuUrl(tableNumber) {
  const base = (process.env.WEB_MENU_BASE_URL || '').trim().replace(/\/+$/, '');
  if (!base) {
    throw new Error(
      'WEB_MENU_BASE_URL is not configured. Set it to the deployed public menu URL, e.g. https://order.fastnfreshcafe.com'
    );
  }
  return `${base}/menu?table=${tableNumber}`;
}

module.exports = { publicMenuUrl };
