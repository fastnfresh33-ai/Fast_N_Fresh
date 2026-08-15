const express = require('express');
const { getPublicMenu, getPublicTable, createPublicOrder } = require('../controllers/publicController');
const { publicMenuLimiter, publicOrderLimiter } = require('../middleware/rateLimiters');

const router = express.Router();

// Intentionally NOT behind `protect` — this is the customer-facing surface.
// Every handler here only ever reads customer-safe data or writes a new,
// server-priced order; nothing here can touch Admin/Staff data.
router.get('/menu', publicMenuLimiter, getPublicMenu);
router.get('/tables/:number', publicMenuLimiter, getPublicTable);
router.post('/orders', publicOrderLimiter, createPublicOrder);

module.exports = router;
