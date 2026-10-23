const express = require('express');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const { z } = require('zod');
const env = require('../config/env');
const { query, tx } = require('../lib/db');
const { audit, clientIp } = require('../lib/audit');
const { unauthorized, badRequest } = require('../lib/errors');
const { validate } = require('../middleware/validate');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: env.isTest ? 1000 : 20,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: { code: 'rate_limited', message: 'Too many attempts. Try again in a few minutes.' } },
});

const password = z.string().min(8, 'Password must be at least 8 characters').max(72)
  .regex(/[A-Za-z]/, 'Password must contain a letter').regex(/[0-9]/, 'Password must contain a number');
const phone = z.string().trim().regex(/^\+?[0-9]{10,15}$/, 'Phone must be 10–15 digits').optional().nullable();

const registerSchema = z.object({
  email: z.email().trim().toLowerCase(),
  password,
  fullName: z.string().trim().min(2).max(100),
  phone,
  city: z.string().trim().min(2).max(60).optional().nullable(),
});
// Note: no `role` field — anything extra the client sends is stripped. Everyone registers as 'user'.

const loginSchema = z.object({ email: z.email().trim().toLowerCase(), password: z.string().min(1).max(200) });
const refreshSchema = z.object({ refreshToken: z.string().min(20).max(200) });

function publicUser(u) {
  return { id: u.id, email: u.email, fullName: u.full_name, phone: u.phone, city: u.city, role: u.role, createdAt: u.created_at };
}

const hashToken = (t) => crypto.createHash('sha256').update(t).digest('hex');

async function issueTokens(db, user) {
  const accessToken = jwt.sign({ sub: user.id }, env.jwtSecret, {
    algorithm: 'HS256', expiresIn: env.accessTokenTtl, audience: 'devicetrust-api',
  });
  const refreshToken = crypto.randomBytes(48).toString('base64url');
  await db.query(
    `insert into refresh_tokens (user_id, token_hash, expires_at) values ($1, $2, now() + make_interval(days => $3))`,
    [user.id, hashToken(refreshToken), env.refreshTokenDays],
  );
  return { accessToken, refreshToken };
}

router.post('/register', authLimiter, validate({ body: registerSchema }), async (req, res) => {
  const { email, fullName, phone: ph, city } = req.body;
  const hash = await bcrypt.hash(req.body.password, 12);
  const result = await tx(async (db) => {
    const { rows } = await db.query(
      `insert into users (email, full_name, phone, city, password_hash) values ($1, $2, $3, $4, $5) returning *`,
      [email, fullName, ph || null, city || null, hash],
    );
    const user = rows[0];
    await audit(db, { actorId: user.id, action: 'user.register', entityType: 'user', entityId: user.id, ip: clientIp(req) });
    const tokens = await issueTokens(db, user);
    return { user: publicUser(user), ...tokens };
  });
  res.status(201).json(result);
});

// Pre-computed hash so login takes the same time whether or not the email exists.
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password-1', 12);

router.post('/login', authLimiter, validate({ body: loginSchema }), async (req, res) => {
  const { rows } = await query('select * from users where email = $1', [req.body.email]);
  const user = rows[0];
  const ok = await bcrypt.compare(req.body.password, user ? user.password_hash : DUMMY_HASH);
  if (!user || !ok) throw unauthorized('Incorrect email or password');
  if (user.status !== 'active') throw unauthorized('This account is suspended');
  const result = await tx(async (db) => {
    await audit(db, { actorId: user.id, action: 'user.login', entityType: 'user', entityId: user.id, ip: clientIp(req) });
    return { user: publicUser(user), ...(await issueTokens(db, user)) };
  });
  res.json(result);
});

// Rotating refresh tokens: each refresh token works once.
router.post('/refresh', authLimiter, validate({ body: refreshSchema }), async (req, res) => {
  const result = await tx(async (db) => {
    const { rows } = await db.query(
      `update refresh_tokens set revoked_at = now()
       where token_hash = $1 and revoked_at is null and expires_at > now()
       returning user_id`,
      [hashToken(req.body.refreshToken)],
    );
    if (!rows[0]) throw unauthorized('Session expired. Please sign in again.');
    const u = await db.query('select * from users where id = $1', [rows[0].user_id]);
    const user = u.rows[0];
    if (!user || user.status !== 'active') throw unauthorized('Session expired. Please sign in again.');
    return { user: publicUser(user), ...(await issueTokens(db, user)) };
  });
  res.json(result);
});

router.post('/logout', validate({ body: refreshSchema }), async (req, res) => {
  await query('update refresh_tokens set revoked_at = now() where token_hash = $1 and revoked_at is null', [hashToken(req.body.refreshToken)]);
  res.status(204).end();
});

router.get('/me', requireAuth, async (req, res) => {
  const { rows } = await query(
    `select u.*,
       (select count(*) from devices d where d.owner_id = u.id)::int as device_count,
       (select count(*) from listings l where l.seller_id = u.id and l.status in ('active','reserved'))::int as active_listing_count,
       (select count(*) from notifications n where n.user_id = u.id and n.read_at is null)::int as unread_notifications
     from users u where u.id = $1`,
    [req.user.id],
  );
  const u = rows[0];
  res.json({
    user: publicUser(u),
    stats: { devices: u.device_count, activeListings: u.active_listing_count, unreadNotifications: u.unread_notifications },
  });
});

const updateMeSchema = z.object({
  fullName: z.string().trim().min(2).max(100).optional(),
  phone,
  city: z.string().trim().min(2).max(60).optional().nullable(),
}).strict();

router.patch('/me', requireAuth, validate({ body: updateMeSchema }), async (req, res) => {
  const b = req.body;
  const { rows } = await query(
    `update users set
       full_name = coalesce($2, full_name),
       phone = case when $3::boolean then $4 else phone end,
       city = case when $5::boolean then $6 else city end
     where id = $1 returning *`,
    [req.user.id, b.fullName ?? null, 'phone' in b, b.phone ?? null, 'city' in b, b.city ?? null],
  );
  res.json({ user: publicUser(rows[0]) });
});

const changePasswordSchema = z.object({ currentPassword: z.string().min(1).max(200), newPassword: password });

router.post('/change-password', requireAuth, authLimiter, validate({ body: changePasswordSchema }), async (req, res) => {
  const { rows } = await query('select password_hash from users where id = $1', [req.user.id]);
  if (!(await bcrypt.compare(req.body.currentPassword, rows[0].password_hash))) throw badRequest('Current password is incorrect');
  const hash = await bcrypt.hash(req.body.newPassword, 12);
  const tokens = await tx(async (db) => {
    await db.query('update users set password_hash = $2 where id = $1', [req.user.id, hash]);
    // Revoke every existing session, then issue fresh tokens for this device only.
    await db.query('update refresh_tokens set revoked_at = now() where user_id = $1 and revoked_at is null', [req.user.id]);
    await audit(db, { actorId: req.user.id, action: 'user.change_password', entityType: 'user', entityId: req.user.id, ip: clientIp(req) });
    return issueTokens(db, req.user);
  });
  res.json(tokens);
});

module.exports = router;
module.exports.publicUser = publicUser;
