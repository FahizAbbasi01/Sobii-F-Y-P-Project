const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const env = require('./config/env');
const { query } = require('./lib/db');
const { notFoundHandler, errorHandler } = require('./middleware/error');
const storage = require('./services/storage');

const app = express();

app.set('trust proxy', 1);
app.disable('x-powered-by');
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
// CORS only matters for the browser admin dashboard; the Flutter app isn't subject to it.
app.use(cors({ origin: env.corsOrigins, credentials: false }));
app.use(express.json({ limit: '100kb' }));

app.get('/health', async (_req, res) => {
  try {
    await query('select 1');
    res.json({ status: 'ok', database: 'ok' });
  } catch {
    res.status(503).json({ status: 'degraded', database: 'unreachable' });
  }
});

if (env.storageDriver === 'local') app.get('/media/*key', storage.localMediaHandler);

const api = express.Router();
api.use('/auth', require('./routes/auth'));
api.use('/registry', require('./routes/registry'));
api.use('/devices', require('./routes/devices'));
api.use('/listings', require('./routes/listings'));
api.use('/purchase-requests', require('./routes/purchases'));
api.use('/transfers', require('./routes/transfers'));
api.use('/stolen-reports', require('./routes/reports'));
api.use('/documents', require('./routes/documents'));
api.use('/notifications', require('./routes/notifications'));
api.use('/admin', require('./routes/admin'));
app.use('/api/v1', api);

app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
