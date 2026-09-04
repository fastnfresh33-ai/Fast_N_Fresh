// Production configuration for the Fast N Fresh customer QR menu.
//
// This static menu has no build step, so the API URL is configured here.
//
// IMPORTANT:
// - Do NOT use localhost in production.
// - Do NOT use 127.0.0.1 in production.
// - Do NOT use a private/local IP address in production.
// - The /api suffix is required because the backend API is mounted at /api.
//
// API URL has been verified against the production backend health endpoint.

window.FNF_CONFIG = {
  API_BASE_URL: 'https://fast-n-fresh-backend.onrender.com/api',
  VERIFIED: true,
};
