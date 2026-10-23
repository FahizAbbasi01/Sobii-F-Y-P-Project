/**
 * Append an audit log entry. Pass a transaction client so the log commits
 * (or rolls back) together with the change it describes.
 */
async function audit(db, { actorId, action, entityType, entityId, metadata = {}, ip = null }) {
  await db.query(
    `insert into audit_logs (actor_id, action, entity_type, entity_id, metadata, ip)
     values ($1, $2, $3, $4, $5, $6)`,
    [actorId || null, action, entityType, entityId ? String(entityId) : null, metadata, ip],
  );
}

async function notify(db, userId, { type, title, body, data = {} }) {
  await db.query(
    `insert into notifications (user_id, type, title, body, data) values ($1, $2, $3, $4, $5)`,
    [userId, type, title, body, data],
  );
}

function clientIp(req) {
  const ip = req.ip || '';
  // Strip IPv6-mapped IPv4 prefix so inet accepts it cleanly.
  const cleaned = ip.replace(/^::ffff:/, '');
  return cleaned || null;
}

module.exports = { audit, notify, clientIp };
