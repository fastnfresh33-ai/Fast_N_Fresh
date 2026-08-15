// Single source of truth for building the public customer QR-menu URL.
//
// The deployed Render Static Site publishes the contents of web/menu
// at its root URL.
//
// Correct:
// https://fast-n-fresh-menu-o5lh.onrender.com/?table=1
//
// Incorrect:
// https://fast-n-fresh-menu-o5lh.onrender.com/menu?table=1
//
// Never hardcode localhost/127.0.0.1/private IPs here.
// The base URL always comes from the environment variable.

function publicMenuUrl(tableNumber) {
  const base = (process.env.WEB_MENU_BASE_URL || '')
    .trim()
    .replace(/\/+$/, '');

  if (!base) {
    throw new Error(
      'WEB_MENU_BASE_URL is not configured. Set it to the deployed public menu URL, e.g. https://fast-n-fresh-menu-o5lh.onrender.com'
    );
  }

  const number = Number(tableNumber);

  if (!Number.isInteger(number) || number < 1) {
    throw new Error(`Invalid table number: ${tableNumber}`);
  }

  return `${base}/?table=${number}`;
}

module.exports = { publicMenuUrl };