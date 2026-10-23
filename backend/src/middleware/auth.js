const jwt = require('jsonwebtoken');
const env = require('../config/env');
const { query } = require('../lib/db');
const { unauthorized, forbidden } = require('../lib/errors');

/**
 * Verifies the bearer token, then re-loads the user from the database.
 * Role and status ALWAYS come from the database, never from the token body
 * or the request, so a demoted or suspended user loses access immediately.
 */
async function loadUser(req, { optional }) {
  const header = req.get('authorization') || '';
  const match = header.match(/^Bearer (.+)$/i);
  if (!match) {
    if (optional) return null;
    throw unauthorized();
  }
  let payload;
  try {
    payload = jwt.verify(match[1], env.jwtSecret, { algorithms: ['HS256'], audience: 'devicetrust-api' });
  } catch {
    throw unauthorized('Session expired or invalid. Please sign in again.');
  }
  const { rows } = await query(
    'select id, email, full_name, phone, city, role, status from users where id = $1',
    [payload.sub],
  );
  const user = rows[0];
  if (!user) throw unauthorized();
  if (user.status !== 'active') throw forbidden('This account is suspended');
  return user;
}

function requireAuth(req, _res, next) {
  loadUser(req, { optional: false }).then((user) => { req.user = user; next(); }, next);
}

function optionalAuth(req, _res, next) {
  loadUser(req, { optional: true }).then((user) => { req.user = user; next(); }, () => { req.user = null; next(); });
}

function requireAdmin(req, _res, next) {
  if (!req.user) return next(unauthorized());
  if (req.user.role !== 'admin') return next(forbidden('Admin access required'));
  return next();
}

module.exports = { requireAuth, optionalAuth, requireAdmin };
