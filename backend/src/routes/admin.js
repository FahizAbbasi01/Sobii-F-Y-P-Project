const express = require('express');
const { z } = require('zod');
const { query, tx } = require('../lib/db');
const { audit, notify, clientIp } = require('../lib/audit');
const { conflict, notFound, badRequest } = require('../lib/errors');
const { validate } = require('../middleware/validate');
const { requireAuth, requireAdmin } = require('../middleware/auth');
const { lockDevice } = require('../services/devices');
const { cancelTransfer, lockTransfer } = require('../services/transfers');
const { validateImei } = require('../lib/imei');
const storage = require('../services/storage');

const router = express.Router();
router.use(requireAuth, requireAdmin);

const idParams = z.object({ id: z.uuid() });
const page = { page: z.coerce.number().int().min(1).default(1), limit: z.coerce.number().int().min(1).max(100).default(25) };
const noteSchema = z.object({ note: z.string().trim().max(1000).optional().nullable() });
const off = (q) => (q.page - 1) * q.limit;

// ---------- Dashboard ----------
router.get('/stats', async (_req, res) => {
  const { rows } = await query(`
    select
      (select count(*) from users)::int as users,
      (select count(*) from users where created_at > now() - interval '7 days')::int as new_users_7d,
      (select count(*) from devices)::int as devices,
      (select count(*) from devices where registry_status = 'reported_stolen')::int as stolen_devices,
      (select count(*) from listings where status = 'active')::int as active_listings,
      (select count(*) from listings where status = 'sold')::int as sold_listings,
      (select count(*) from ownership_transfers where status = 'completed')::int as completed_transfers,
      (select count(*) from ownership_transfers where status = 'pending')::int as pending_transfers,
      (select count(*) from stolen_reports where status = 'pending')::int as pending_reports,
      (select count(*) from documents where status = 'pending')::int as pending_documents,
      (select count(*) from disputes where status = 'open')::int as open_disputes,
      (select count(*) from imei_lookups where created_at > now() - interval '24 hours')::int as lookups_24h`);
  const daily = await query(`
    select to_char(day, 'YYYY-MM-DD') as day,
      (select count(*) from devices where created_at::date = day)::int as registrations,
      (select count(*) from ownership_transfers where completed_at::date = day)::int as transfers
    from generate_series(current_date - 13, current_date, interval '1 day') as day order by day`);
  res.json({ totals: rows[0], daily: daily.rows });
});

/**
 * Suspicious-activity flags. Rule-based heuristics, meant to point an admin
 * at things worth a look — not automatic verdicts.
 */
router.get('/flags', async (_req, res) => {
  const [stolenLookups, fastTransfers, rejectedReporters, bulkRegistrations, lowPrices] = await Promise.all([
    query(`select l.imei, count(*)::int as lookups, max(l.created_at) as last_at, d.brand, d.model
           from imei_lookups l join device_imeis i on i.imei = l.imei join devices d on d.id = i.device_id
           where l.result = 'reported_stolen' and l.created_at > now() - interval '30 days'
           group by l.imei, d.brand, d.model order by lookups desc limit 20`),
    query(`select d.id as device_id, d.brand, d.model, count(*)::int as transfers
           from ownership_transfers t join devices d on d.id = t.device_id
           where t.status = 'completed' and t.completed_at > now() - interval '30 days'
           group by d.id having count(*) >= 3 order by transfers desc limit 20`),
    query(`select u.id as user_id, u.full_name, u.email, count(*)::int as rejected
           from stolen_reports r join users u on u.id = r.reporter_id
           where r.status = 'rejected' group by u.id having count(*) >= 2 order by rejected desc limit 20`),
    query(`select u.id as user_id, u.full_name, u.email, count(*)::int as devices
           from devices d join ownership_history h on h.device_id = d.id and h.acquired_via = 'registration'
           join users u on u.id = h.owner_id
           where h.acquired_at > now() - interval '7 days' group by u.id having count(*) >= 5 order by devices desc limit 20`),
    query(`with m as (select d.brand, d.model, percentile_cont(0.5) within group (order by l.price) as median, count(*) as n
                      from listings l join devices d on d.id = l.device_id where l.status in ('active','sold') group by d.brand, d.model)
           select l.id as listing_id, l.title, l.price, round(m.median::numeric, 0) as median_price
           from listings l join devices d on d.id = l.device_id join m on m.brand = d.brand and m.model = d.model
           where l.status = 'active' and m.n >= 3 and l.price < m.median * 0.4 limit 20`),
  ]);
  const flags = [
    ...stolenLookups.rows.map((r) => ({ type: 'stolen_imei_lookups', severity: r.lookups >= 3 ? 'high' : 'medium', message: `Stolen ${r.brand} ${r.model} (IMEI ${r.imei}) looked up ${r.lookups}× in 30 days`, ref: { imei: r.imei }, at: r.last_at })),
    ...fastTransfers.rows.map((r) => ({ type: 'rapid_transfers', severity: 'medium', message: `${r.brand} ${r.model} changed owners ${r.transfers}× in 30 days`, ref: { deviceId: r.device_id } })),
    ...rejectedReporters.rows.map((r) => ({ type: 'rejected_reports', severity: 'medium', message: `${r.full_name} (${r.email}) has ${r.rejected} rejected stolen reports`, ref: { userId: r.user_id } })),
    ...bulkRegistrations.rows.map((r) => ({ type: 'bulk_registration', severity: 'low', message: `${r.full_name} registered ${r.devices} devices in 7 days`, ref: { userId: r.user_id } })),
    ...lowPrices.rows.map((r) => ({ type: 'price_anomaly', severity: 'low', message: `"${r.title}" listed at ${r.price}, median is ${r.median_price}`, ref: { listingId: r.listing_id } })),
  ];
  res.json({ flags });
});

// ---------- Users ----------
router.get('/users', validate({ query: z.object({ q: z.string().trim().max(80).optional(), status: z.enum(['active', 'suspended']).optional(), ...page }) }), async (req, res) => {
  const params = [];
  const where = ['true'];
  if (req.q.q) { params.push(`%${req.q.q}%`); where.push(`(u.email ilike $${params.length} or u.full_name ilike $${params.length})`); }
  if (req.q.status) { params.push(req.q.status); where.push(`u.status = $${params.length}`); }
  const w = where.join(' and ');
  const [list, count] = await Promise.all([
    query(`select u.id, u.email, u.full_name, u.phone, u.city, u.role, u.status, u.created_at,
             (select count(*) from devices d where d.owner_id = u.id)::int as devices,
             (select count(*) from listings l where l.seller_id = u.id)::int as listings
           from users u where ${w} order by u.created_at desc limit ${req.q.limit} offset ${off(req.q)}`, params),
    query(`select count(*)::int as n from users u where ${w}`, params),
  ]);
  res.json({ users: list.rows, total: count.rows[0].n });
});

router.post('/users/:id/status', validate({ params: idParams, body: z.object({ status: z.enum(['active', 'suspended']), note: z.string().trim().max(500).optional() }) }), async (req, res) => {
  if (req.params.id === req.user.id) throw badRequest('You cannot change your own status');
  await tx(async (db) => {
    const { rows } = await db.query('update users set status = $2 where id = $1 and role <> \'admin\' returning id', [req.params.id, req.body.status]);
    if (!rows[0]) throw notFound('User not found (admins cannot be suspended here)');
    if (req.body.status === 'suspended') {
      await db.query('update refresh_tokens set revoked_at = now() where user_id = $1 and revoked_at is null', [req.params.id]);
    }
    await audit(db, { actorId: req.user.id, action: `admin.user_${req.body.status}`, entityType: 'user', entityId: req.params.id, metadata: { note: req.body.note || null }, ip: clientIp(req) });
  });
  res.json({ ok: true });
});

// ---------- Listings ----------
router.get('/listings', validate({ query: z.object({ status: z.enum(['active', 'reserved', 'sold', 'withdrawn', 'removed']).optional(), q: z.string().trim().max(80).optional(), ...page }) }), async (req, res) => {
  const params = [];
  const where = ['true'];
  if (req.q.status) { params.push(req.q.status); where.push(`l.status = $${params.length}`); }
  if (req.q.q) { params.push(`%${req.q.q}%`); where.push(`(l.title ilike $${params.length} or d.brand ilike $${params.length} or d.model ilike $${params.length})`); }
  const w = where.join(' and ');
  const [list, count] = await Promise.all([
    query(`select l.id, l.title, l.price, l.condition, l.city, l.status, l.created_at, d.id as device_id, d.brand, d.model, d.registry_status,
                  u.id as seller_id, u.full_name as seller_name, u.email as seller_email
           from listings l join devices d on d.id = l.device_id join users u on u.id = l.seller_id
           where ${w} order by l.created_at desc limit ${req.q.limit} offset ${off(req.q)}`, params),
    query(`select count(*)::int as n from listings l join devices d on d.id = l.device_id where ${w}`, params),
  ]);
  res.json({ listings: list.rows, total: count.rows[0].n });
});

router.post('/listings/:id/remove', validate({ params: idParams, body: noteSchema }), async (req, res) => {
  await tx(async (db) => {
    const l = (await db.query('select * from listings where id = $1', [req.params.id])).rows[0];
    if (!l) throw notFound('Listing not found');
    await lockDevice(db, l.device_id);
    const listing = (await db.query('select * from listings where id = $1 for update', [l.id])).rows[0];
    if (!['active', 'reserved'].includes(listing.status)) throw conflict(`Listing is already ${listing.status}`);
    const t = (await db.query(`select t.* from ownership_transfers t join purchase_requests pr on pr.id = t.purchase_request_id
                                where pr.listing_id = $1 and t.status in ('pending','disputed') for update of t`, [l.id])).rows[0];
    if (t) await cancelTransfer(db, t, { actorId: req.user.id, reason: 'The listing was removed by an admin.', ip: clientIp(req) });
    await db.query(`update listings set status = 'removed' where id = $1`, [l.id]);
    await db.query(`update purchase_requests set status = 'rejected' where listing_id = $1 and status in ('pending','accepted')`, [l.id]);
    await notify(db, l.seller_id, { type: 'listing.removed', title: 'Listing removed', body: `Your listing "${l.title}" was removed by a moderator.${req.body.note ? ` Reason: ${req.body.note}` : ''}`, data: { listingId: l.id } });
    await audit(db, { actorId: req.user.id, action: 'admin.listing_remove', entityType: 'listing', entityId: l.id, metadata: { note: req.body.note || null }, ip: clientIp(req) });
  });
  res.json({ ok: true });
});

// ---------- Stolen reports ----------
router.get('/reports', validate({ query: z.object({ status: z.enum(['pending', 'approved', 'rejected']).optional(), ...page }) }), async (req, res) => {
  const params = [];
  let w = 'true';
  if (req.q.status) { params.push(req.q.status); w = `r.status = $1`; }
  const [list, count] = await Promise.all([
    query(`select r.*, d.brand, d.model, d.registry_status, u.full_name as reporter_name, u.email as reporter_email,
             (select string_agg(i.imei, ', ' order by i.slot) from device_imeis i where i.device_id = d.id) as imeis,
             (select count(*) from documents doc where doc.stolen_report_id = r.id)::int as document_count
           from stolen_reports r join devices d on d.id = r.device_id join users u on u.id = r.reporter_id
           where ${w} order by (r.status = 'pending') desc, r.created_at desc limit ${req.q.limit} offset ${off(req.q)}`, params),
    query(`select count(*)::int as n from stolen_reports r where ${w}`, params),
  ]);
  res.json({ reports: list.rows, total: count.rows[0].n });
});

async function lockReport(db, id) {
  const peek = (await db.query('select device_id from stolen_reports where id = $1', [id])).rows[0];
  if (!peek) throw notFound('Report not found');
  const device = await lockDevice(db, peek.device_id);
  const report = (await db.query('select * from stolen_reports where id = $1 for update', [id])).rows[0];
  if (report.status !== 'pending') throw conflict(`This report is already ${report.status}`);
  return { device, report };
}

router.post('/reports/:id/approve', validate({ params: idParams, body: noteSchema }), async (req, res) => {
  await tx(async (db) => {
    const { device, report } = await lockReport(db, req.params.id);
    await db.query(`update stolen_reports set status = 'approved', reviewed_by = $2, review_note = $3, reviewed_at = now() where id = $1`, [report.id, req.user.id, req.body.note || null]);
    await db.query(`update devices set registry_status = 'reported_stolen' where id = $1`, [device.id]);
    // Belt and braces: nothing about this device may stay on the market or in flight.
    const transfers = await db.query(`select * from ownership_transfers where device_id = $1 and status in ('pending','disputed') for update`, [device.id]);
    for (const t of transfers.rows) await cancelTransfer(db, t, { actorId: req.user.id, reason: 'The device was confirmed as stolen.', ip: clientIp(req) });
    const live = await db.query(`update listings set status = 'removed' where device_id = $1 and status in ('active','reserved') returning id`, [device.id]);
    for (const l of live.rows) await db.query(`update purchase_requests set status = 'rejected' where listing_id = $1 and status in ('pending','accepted')`, [l.id]);
    await notify(db, report.reporter_id, { type: 'report.approved', title: 'Stolen report approved', body: `Your ${device.brand} ${device.model} is now flagged as stolen in the DeviceTrust registry.`, data: { reportId: report.id, deviceId: device.id } });
    await audit(db, { actorId: req.user.id, action: 'admin.report_approve', entityType: 'stolen_report', entityId: report.id, metadata: { deviceId: device.id, note: req.body.note || null }, ip: clientIp(req) });
  });
  res.json({ ok: true });
});

router.post('/reports/:id/reject', validate({ params: idParams, body: noteSchema }), async (req, res) => {
  await tx(async (db) => {
    const { device, report } = await lockReport(db, req.params.id);
    await db.query(`update stolen_reports set status = 'rejected', reviewed_by = $2, review_note = $3, reviewed_at = now() where id = $1`, [report.id, req.user.id, req.body.note || null]);
    await notify(db, report.reporter_id, { type: 'report.rejected', title: 'Stolen report not approved', body: `Your report for the ${device.brand} ${device.model} was not approved.${req.body.note ? ` Note: ${req.body.note}` : ''}`, data: { reportId: report.id } });
    await audit(db, { actorId: req.user.id, action: 'admin.report_reject', entityType: 'stolen_report', entityId: report.id, metadata: { note: req.body.note || null }, ip: clientIp(req) });
  });
  res.json({ ok: true });
});

// ---------- Documents ----------
router.get('/documents', validate({ query: z.object({ status: z.enum(['pending', 'approved', 'rejected']).optional(), ...page }) }), async (req, res) => {
  const params = [];
  let w = 'true';
  if (req.q.status) { params.push(req.q.status); w = 'doc.status = $1'; }
  const { rows } = await query(
    `select doc.id, doc.kind, doc.status, doc.mime_type, doc.size_bytes, doc.device_id, doc.stolen_report_id, doc.review_note, doc.created_at,
            u.full_name as owner_name, u.email as owner_email, d.brand, d.model
     from documents doc join users u on u.id = doc.owner_id left join devices d on d.id = doc.device_id
     where ${w} order by doc.created_at desc limit ${req.q.limit} offset ${off(req.q)}`, params);
  res.json({ documents: rows });
});

router.get('/documents/:id/url', validate({ params: idParams }), async (req, res) => {
  const { rows } = await query('select storage_path from documents where id = $1', [req.params.id]);
  if (!rows[0]) throw notFound('Document not found');
  await audit({ query }, { actorId: req.user.id, action: 'admin.document_view', entityType: 'document', entityId: req.params.id, ip: clientIp(req) });
  res.json({ url: await storage.signedUrl(rows[0].storage_path) });
});

router.post('/documents/:id/review', validate({ params: idParams, body: z.object({ decision: z.enum(['approved', 'rejected']), note: z.string().trim().max(1000).optional().nullable() }) }), async (req, res) => {
  await tx(async (db) => {
    const { rows } = await db.query(
      `update documents set status = $2, review_note = $3, reviewed_by = $4 where id = $1 and status = 'pending' returning owner_id, kind`,
      [req.params.id, req.body.decision, req.body.note || null, req.user.id],
    );
    if (!rows[0]) throw conflict('Document not found or already reviewed');
    await notify(db, rows[0].owner_id, { type: `document.${req.body.decision}`, title: `Document ${req.body.decision}`, body: `Your ${rows[0].kind.replace('_', ' ')} was ${req.body.decision}.`, data: { documentId: req.params.id } });
    await audit(db, { actorId: req.user.id, action: `admin.document_${req.body.decision}`, entityType: 'document', entityId: req.params.id, ip: clientIp(req) });
  });
  res.json({ ok: true });
});

// ---------- Disputes ----------
router.get('/disputes', validate({ query: z.object({ status: z.enum(['open', 'resolved', 'rejected']).optional(), ...page }) }), async (req, res) => {
  const params = [];
  let w = 'true';
  if (req.q.status) { params.push(req.q.status); w = 'x.status = $1'; }
  const { rows } = await query(
    `select x.*, u.full_name as raised_by_name, u.email as raised_by_email, d.brand, d.model,
            t.status as transfer_status, f.full_name as from_name, r.full_name as to_name
     from disputes x join users u on u.id = x.raised_by join devices d on d.id = x.device_id
     left join ownership_transfers t on t.id = x.transfer_id
     left join users f on f.id = t.from_user_id left join users r on r.id = t.to_user_id
     where ${w} order by (x.status = 'open') desc, x.created_at desc limit ${req.q.limit} offset ${off(req.q)}`, params);
  res.json({ disputes: rows });
});

/**
 * action: 'cancel_transfer' → transfer cancelled, listing re-opened.
 *         'resume_transfer' → dispute dismissed, transfer back to pending (both must still confirm).
 */
router.post('/disputes/:id/resolve', validate({ params: idParams, body: z.object({ action: z.enum(['cancel_transfer', 'resume_transfer']), resolution: z.string().trim().min(5).max(2000) }) }), async (req, res) => {
  await tx(async (db) => {
    const d = (await db.query('select * from disputes where id = $1', [req.params.id])).rows[0];
    if (!d) throw notFound('Dispute not found');
    if (d.status !== 'open') throw conflict(`Dispute is already ${d.status}`);
    if (d.transfer_id) {
      const { transfer } = await lockTransfer(db, d.transfer_id);
      if (transfer.status === 'disputed') {
        if (req.body.action === 'cancel_transfer') {
          await cancelTransfer(db, transfer, { actorId: req.user.id, reason: `Dispute resolved by admin: ${req.body.resolution}`, ip: clientIp(req) });
        } else {
          await db.query(`update ownership_transfers set status = 'pending' where id = $1`, [transfer.id]);
        }
      }
      for (const uid of [transfer.from_user_id, transfer.to_user_id]) {
        await notify(db, uid, { type: 'dispute.resolved', title: 'Dispute resolved', body: req.body.resolution, data: { disputeId: d.id, transferId: transfer.id } });
      }
    }
    await db.query(`update disputes set status = $2, resolution = $3, resolved_by = $4, resolved_at = now() where id = $1`,
      [d.id, req.body.action === 'cancel_transfer' ? 'resolved' : 'rejected', req.body.resolution, req.user.id]);
    await audit(db, { actorId: req.user.id, action: 'admin.dispute_resolve', entityType: 'dispute', entityId: d.id, metadata: req.body, ip: clientIp(req) });
  });
  res.json({ ok: true });
});

// ---------- Devices & history ----------
router.get('/devices', validate({ query: z.object({ q: z.string().trim().max(80).optional(), ...page }) }), async (req, res) => {
  const params = [];
  let w = 'true';
  if (req.q.q) {
    const digits = req.q.q.replace(/\D/g, '');
    params.push(`%${req.q.q}%`, digits.length >= 4 ? `%${digits}%` : '__none__');
    w = `(d.brand ilike $1 or d.model ilike $1 or u.email ilike $1 or exists(select 1 from device_imeis i where i.device_id = d.id and i.imei like $2))`;
  }
  const { rows } = await query(
    `select d.id, d.brand, d.model, d.storage_gb, d.registry_status, d.created_at, u.full_name as owner_name, u.email as owner_email,
            (select string_agg(i.imei, ', ' order by i.slot) from device_imeis i where i.device_id = d.id) as imeis
     from devices d join users u on u.id = d.owner_id where ${w} order by d.created_at desc limit ${req.q.limit} offset ${off(req.q)}`, params);
  res.json({ devices: rows });
});

router.get('/devices/:id', validate({ params: idParams }), async (req, res) => {
  const d = (await query(
    `select d.*, u.full_name as owner_name, u.email as owner_email,
            (select json_agg(json_build_object('imei', i.imei, 'slot', i.slot) order by i.slot) from device_imeis i where i.device_id = d.id) as imeis
     from devices d join users u on u.id = d.owner_id where d.id = $1`, [req.params.id])).rows[0];
  if (!d) throw notFound('Device not found');
  const [history, transfers, reports, listings, auditRows] = await Promise.all([
    query(`select h.*, u.full_name, u.email from ownership_history h join users u on u.id = h.owner_id where h.device_id = $1 order by h.acquired_at`, [d.id]),
    query(`select t.*, f.full_name as from_name, r.full_name as to_name from ownership_transfers t join users f on f.id = t.from_user_id join users r on r.id = t.to_user_id where t.device_id = $1 order by t.created_at desc`, [d.id]),
    query(`select r.*, u.full_name as reporter_name from stolen_reports r join users u on u.id = r.reporter_id where r.device_id = $1 order by r.created_at desc`, [d.id]),
    query(`select id, title, price, status, created_at from listings where device_id = $1 order by created_at desc`, [d.id]),
    query(`select a.*, u.full_name as actor_name from audit_logs a left join users u on u.id = a.actor_id
           where (a.entity_type = 'device' and a.entity_id = $1) or a.metadata->>'deviceId' = $1 order by a.created_at desc limit 100`, [d.id]),
  ]);
  res.json({ device: d, ownershipHistory: history.rows, transfers: transfers.rows, reports: reports.rows, listings: listings.rows, audit: auditRows.rows });
});

router.get('/registry/:imei', async (req, res) => {
  const v = validateImei(req.params.imei);
  if (!v.valid) throw badRequest(v.reason);
  const { rows } = await query('select device_id from device_imeis where imei = $1', [v.imei]);
  res.json({ deviceId: rows[0]?.device_id ?? null });
});

// ---------- Audit log ----------
router.get('/audit', validate({ query: z.object({ action: z.string().trim().max(60).optional(), entityType: z.string().trim().max(40).optional(), ...page }) }), async (req, res) => {
  const params = [];
  const where = ['true'];
  if (req.q.action) { params.push(`${req.q.action}%`); where.push(`a.action like $${params.length}`); }
  if (req.q.entityType) { params.push(req.q.entityType); where.push(`a.entity_type = $${params.length}`); }
  const { rows } = await query(
    `select a.*, u.full_name as actor_name, u.email as actor_email from audit_logs a left join users u on u.id = a.actor_id
     where ${where.join(' and ')} order by a.created_at desc limit ${req.q.limit} offset ${off(req.q)}`, params);
  res.json({ entries: rows });
});

module.exports = router;
