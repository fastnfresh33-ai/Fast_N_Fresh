// Single source of truth for building the public customer QR-menu URL.
//
// The deployed Render Static Site publishes the contents of web/menu
// at its root URL.
//
// Correct:
// https://fast-n-fresh-backend.onrender.com/menu?table=1
//
// Incorrect:
// https://fast-n-fresh-backend.onrender.com/menu/menu?table=1
//
// Never hardcode localhost/127.0.0.1/private IPs here.
// The base URL always comes from the environment variable.

function publicMenuUrl(tableNumber) {
  // Prefer an explicitly configured public menu host, but fall back to the
  // same Render backend. The backend serves /menu, so QR ordering does not
  // depend on a second Render Static Site being deployed.
  const base = (process.env.WEB_MENU_BASE_URL || 'https://fast-n-fresh-backend.onrender.com/menu')
    .trim()
    .replace(/\/+$/, '');

  const number = Number(tableNumber);

  if (!Number.isInteger(number) || number < 1) {
    throw new Error(`Invalid table number: ${tableNumber}`);
  }

  return `${base}?table=${number}`;
}

module.exports = { publicMenuUrl };