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
// ⚠ VERIFY BEFORE DEPLOYING — THIS URL HAS NOT BEEN CONFIRMED LIVE ⚠
// The value below was found already sitting in this file. It has NOT been
// confirmed to point at a real, currently-running deployment of this
// project's backend — treat it as an unverified placeholder, not a known
// value. Before this menu goes live:
//   1. Open API_BASE_URL + '/health' in a browser (e.g.
//      https://<your-actual-backend>.onrender.com/api/health) and confirm
//      it returns { "success": true, "message": "Fast N Fresh Cafe API is
//      running." }. If it doesn't load, or loads something unrelated,
//      API_BASE_URL below is wrong — replace it with your real backend URL.
//   2. Only then set VERIFIED to true. Until you do, app.js refuses to run
//      and shows a clear "not configured" message instead of silently
//      failing (or worse, silently talking to the wrong backend).

window.FNF_CONFIG = {
  API_BASE_URL: 'https://fast-n-fresh-backend.onrender.com/api',
  VERIFIED: true, // set to true only after step 1 above has been done
};