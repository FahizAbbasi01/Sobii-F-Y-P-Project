const express = require('express');
const { z } = require('zod');
const { query } = require('../lib/db');
const { validate } = require('../middleware/validate');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();
router.use(requireAuth);

router.get('/', validate({ query: z.object({ unread: z.enum(['true', 'false']).optional() }) }), async (req, res) => {
  const unreadOnly = req.q.unread === 'true';
  const { rows } = await query(
    `select * from notifications where user_id = $1 ${unreadOnly ? 'and read_at is null' : ''} order by created_at desc limit 100`,
    [req.user.id],
  );
  const unread = await query('select count(*)::int as n from notifications where user_id = $1 and read_at is null', [req.user.id]);
  res.json({
    unreadCount: unread.rows[0].n,
    notifications: rows.map((n) => ({ id: n.id, type: n.type, title: n.title, body: n.body, data: n.data, read: !!n.read_at, createdAt: n.created_at })),
  });
});

// user_id in the WHERE clause means you can only mark your own notifications.
router.post('/:id/read', validate({ params: z.object({ id: z.uuid() }) }), async (req, res) => {
  await query('update notifications set read_at = coalesce(read_at, now()) where id = $1 and user_id = $2', [req.params.id, req.user.id]);
  res.status(204).end();
});

router.post('/read-all', async (req, res) => {
  await query('update notifications set read_at = now() where user_id = $1 and read_at is null', [req.user.id]);
  res.status(204).end();
});

module.exports = router;
