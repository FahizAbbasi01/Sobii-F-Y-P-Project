const multer = require('multer');
const { ApiError } = require('../lib/errors');
const env = require('../config/env');

// Map PostgreSQL constraint violations to safe, user-facing messages.
const CONSTRAINT_MESSAGES = {
  device_imeis_pkey: 'This IMEI is already registered to a device',
  users_email_key: 'An account with this email already exists',
  listings_one_live_per_device: 'This device already has a live listing',
  purchase_requests_one_open: 'You already have an open request for this listing',
  purchase_requests_one_accepted: 'Another request has already been accepted for this listing',
  ownership_transfers_one_pending: 'This device already has a transfer in progress',
  stolen_reports_one_pending: 'A stolen report for this device is already under review',
};

function notFoundHandler(req, res) {
  res.status(404).json({ error: { code: 'not_found', message: `No route for ${req.method} ${req.path}` } });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, _next) {
  if (err instanceof ApiError) {
    return res.status(err.status).json({ error: { code: err.code, message: err.message, details: err.details } });
  }
  if (err instanceof multer.MulterError) {
    const message = err.code === 'LIMIT_FILE_SIZE' ? 'File is too large (max 5 MB)' : err.message;
    return res.status(400).json({ error: { code: 'bad_upload', message } });
  }
  if (err && err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: { code: 'bad_request', message: 'Malformed JSON body' } });
  }
  if (err && err.code === '23505') {
    const message = CONSTRAINT_MESSAGES[err.constraint] || 'This record already exists';
    return res.status(409).json({ error: { code: 'conflict', message } });
  }
  if (err && (err.code === '23514' || err.code === '22P02' || err.code === '23503')) {
    return res.status(400).json({ error: { code: 'bad_request', message: 'Invalid data' } });
  }
  // Unknown error: log server-side, never leak internals to the client.
  if (!env.isTest) console.error(err);
  return res.status(500).json({ error: { code: 'internal', message: 'Something went wrong. Please try again.' } });
}

module.exports = { notFoundHandler, errorHandler };
