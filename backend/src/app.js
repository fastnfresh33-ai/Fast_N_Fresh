require('dotenv').config();

const dns = require('dns');
dns.setServers(['8.8.8.8', '1.1.1.1']);

const express = require('express');
const path = require('path');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const mongoSanitize = require('express-mongo-sanitize');

const connectDB = require('./config/db');
const routes = require('./routes');
const { notFound, errorHandler } = require('./middleware/errorHandler');

const app = express();

// Security & parsing middleware
// crossOriginResourcePolicy relaxed so product images can be loaded by the
// Flutter app (a different origin) — everything else stays locked down.
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(express.json({ limit: '2mb' }));
app.use(mongoSanitize());

const allowedOrigins = (process.env.CORS_ORIGIN || '*')
  .split(',')
  .map((o) => o.trim());

app.use(
  cors({
    origin: allowedOrigins.includes('*') ? true : allowedOrigins,
  })
);

if (process.env.NODE_ENV !== 'test') {
  app.use(
    morgan(
      process.env.NODE_ENV === 'production' ? 'combined' : 'dev'
    )
  );
}

// Serves uploaded product photos at e.g. GET /uploads/products/xyz.jpg —
// the Flutter app stores/loads the relative URL returned at upload time and
// resolves it against ApiConfig.baseUrl, so no path is ever hard-coded.
app.use(
  '/uploads',
  express.static(path.join(__dirname, '..', 'uploads'))
);

app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'FAST N FRESH CAFE API',
    version: '1.0.0',
  });
});

app.use('/api', routes);

app.use(notFound);
app.use(errorHandler);

const PORT = process.env.PORT || 5000;

async function start() {
  await connectDB();

  app.listen(PORT, () => {
    console.log(
      `Fast N Fresh Cafe API listening on port ${PORT} [${process.env.NODE_ENV || 'development'}]`
    );
  });
}

start();

module.exports = app;