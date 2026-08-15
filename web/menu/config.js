// Deployment configuration for the customer QR menu.
//
// EDIT THIS FILE per environment before deploying — there is no build step,
// so this is the equivalent of an env var for this static site.
//
// NEVER set API_BASE_URL to localhost/127.0.0.1/a private IP in production;
// use the real deployed backend API URL (the same one the Flutter app's
// API_BASE_URL points to, e.g. https://api.fastnfreshcafe.com/api).
window.FNF_CONFIG = {
  API_BASE_URL: 'https://your-deployed-api-domain.com/api',
};
