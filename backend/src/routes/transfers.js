const express = require('express');
const { z } = require('zod');
const { query, tx } = require('../lib/db');
const { audit, notify, clientIp } = require('../lib/audit');
const { conflict, notFound, badRequest } = require('../lib/errors');
const { validate } = require('../middleware/validate');
const { requireAuth } = require('../middleware/auth');
const { lockDevice, assertOwner, assertNotStolen, hasPendingReport } = require('../services/devices');
const { lockTransfer, assertParticipant, completeIfReady, cancelTransfer } = require('../services/transfers');

const router = express.Router();
router.use(requireAuth);

const idParams = z.object({ id: z.uuid() });

const TRANSFER_SQL = `
  select t.*, d.brand, d.model, d.storage_gb, d.registry_status,
         f.full_name as from_name, f.email as from_email, r.full_name as to_name, r.email as to_email,
         (select right(i.imei, 4) from device_imeis i where i.device_id = d.id and i.slot = 1) as imei_last4
  from ownership_transfers t
  join devices d on d.id = t.device_id
  join users f on f.id = t.from_user_id
  join users r on r.id = t.to_user_id`;

function dto(r, userId) {
  const role = r.from_user_id === userId ? 'sender' : 'recipient';
  return {
    id: r.id,
    status: r.status,
    role,
    device: { id: r.device_id, brand: r.brand, model: r.model, storageGb: r.storage_gb, imeiLast4: r.imei_last4, registryStatus: r.registry_status },
    from: { id: r.from_user_id, name: r.from_name },
    to: { id: r.to_user_id, name: r.to_name, email: role === 'sender' ? r.to_email : undefined },
    purchaseRequestId: r.purchase_request_id,
    senderConfirmedAt: r.seller_confirmed_at,
    recipientConfirmedAt: r.buyer_confirmed_at,
    youConfirmed: role === 'sender' ? !!r.seller_confirmed_at : !!r.buyer_confirmed_at,
    createdAt: r.created_at,
    completedAt: r.completed_at,
  };
}

async function load(id, userId) {
  const { rows } = await query(`${TRANSFER_SQL} where t.id = $1`, [id]);
  return dto(rows[0], userId);
}

// Direct transfer (gift / offline sale) to another registered user by email.
const createSchema = z.object({ deviceId: z.uuid(), recipientEmail: z.email().trim().toLowerCase() });

router.post('/', validate({ body: createSchema }), async (req, res) => {
  const id = await tx(async (db) => {
    const device = await lockDevice(db, req.body.deviceId);
    assertOwner(device, req.user);
    assertNotStolen(device);
    if (await hasPendingReport(db, device.id)) throw conflict('This device has a stolen report under review', 'report_pending');
    const live = await db.query(`select 1 from listings where device_id = $1 and status in ('active','reserved')`, [device.id]);
    if (live.rows.length) throw conflict('Withdraw the marketplace listing for this device before transferring it directly', 'listing_live');
    const to = (await db.query(`select id, status from users where email = $1`, [req.body.recipientEmail])).rows[0];
    if (!to || to.status !== 'active') throw notFound('No active DeviceTrust user with that email');
    if (to.id === req.user.id) throw badRequest('You already own this device');
    // Unique index ownership_transfers_one_pending blocks duplicate active transfers (→ 409).
    const { rows } = await db.query(
      `insert into ownership_transfers (device_id, from_user_id, to_user_id) values ($1, $2, $3) returning id`,
      [device.id, req.user.id, to.id],
    );
    await notify(db, to.id, {
      type: 'transfer.incoming', title: 'Incoming ownership transfer',
      body: `${req.user.full_name} wants to transfer a ${device.brand} ${device.model} to you. Review and confirm.`,
      data: { transferId: rows[0].id },
    });
    await audit(db, { actorId: req.user.id, action: 'transfer.create', entityType: 'transfer', entityId: rows[0].id, metadata: { deviceId: device.id, to: to.id }, ip: clientIp(req) });
    return rows[0].id;
  });
  res.status(201).json({ transfer: await load(id, req.user.id) });
});

const listSchema = z.object({ status: z.enum(['pending', 'completed', 'cancelled', 'disputed']).optional() });

router.get('/', validate({ query: listSchema }), async (req, res) => {
  const params = [req.user.id];
  let where = '(t.from_user_id = $1 or t.to_user_id = $1)';
  if (req.q.status) { params.push(req.q.status); where += ` and t.status = $2`; }
  const { rows } = await query(`${TRANSFER_SQL} where ${where} order by t.created_at desc limit 200`, params);
  res.json({ transfers: rows.map((r) => dto(r, req.user.id)) });
});

router.get('/:id', validate({ params: idParams }), async (req, res) => {
  const { rows } = await query(`${TRANSFER_SQL} where t.id = $1`, [req.params.id]);
  const r = rows[0];
  if (!r || (r.from_user_id !== req.user.id && r.to_user_id !== req.user.id && req.user.role !== 'admin')) throw notFound('Transfer not found');
  res.json({ transfer: dto(r, req.user.id) });
});

// Each party confirms once. Ownership changes only when both have confirmed.
router.post('/:id/confirm', validate({ params: idParams }), async (req, res) => {
  const completed = await tx(async (db) => {
    const { device, transfer } = await lockTransfer(db, req.params.id);
    assertParticipant(transfer, req.user);
    if (transfer.status !== 'pending') throw conflict(`This transfer is ${transfer.status}`);
    assertNotStolen(device);
    const isSender = transfer.from_user_id === req.user.id;
    const column = isSender ? 'seller_confirmed_at' : 'buyer_confirmed_at';
    if (transfer[column]) throw conflict('You have already confirmed this transfer');
    const { rows } = await db.query(`update ownership_transfers set ${column} = now() where id = $1 returning *`, [transfer.id]);
    await audit(db, { actorId: req.user.id, action: `transfer.confirm_${isSender ? 'sender' : 'recipient'}`, entityType: 'transfer', entityId: transfer.id, ip: clientIp(req) });
    const done = await completeIfReady(db, device, rows[0], { actorId: req.user.id, ip: clientIp(req) });
    if (!done) {
      const other = isSender ? transfer.to_user_id : transfer.from_user_id;
      await notify(db, other, { type: 'transfer.confirm_needed', title: 'Your confirmation is needed', body: `${req.user.full_name} confirmed the ${device.brand} ${device.model} transfer. Confirm to finish it.`, data: { transferId: transfer.id } });
    }
    return done;
  });
  res.json({ completed, transfer: await load(req.params.id, req.user.id) });
});

router.post('/:id/cancel', validate({ params: idParams }), async (req, res) => {
  await tx(async (db) => {
    const { transfer } = await lockTransfer(db, req.params.id);
    assertParticipant(transfer, req.user);
    if (transfer.status !== 'pending') throw conflict(`This transfer is ${transfer.status}`);
    await cancelTransfer(db, transfer, { actorId: req.user.id, ip: clientIp(req) });
  });
  res.json({ transfer: await load(req.params.id, req.user.id) });
});

// Either party can freeze a pending transfer by raising a dispute; an admin resolves it.
const disputeSchema = z.object({ reason: z.string().trim().min(10).max(2000) });

router.post('/:id/dispute', validate({ params: idParams, body: disputeSchema }), async (req, res) => {
  await tx(async (db) => {
    const { transfer, device } = await lockTransfer(db, req.params.id);
    assertParticipant(transfer, req.user);
    if (transfer.status !== 'pending') throw conflict('Only pending transfers can be disputed');
    await db.query(`update ownership_transfers set status = 'disputed' where id = $1`, [transfer.id]);
    const d = await db.query(
      `insert into disputes (transfer_id, device_id, raised_by, reason) values ($1, $2, $3, $4) returning id`,
      [transfer.id, device.id, req.user.id, req.body.reason],
    );
    const other = transfer.from_user_id === req.user.id ? transfer.to_user_id : transfer.from_user_id;
    await notify(db, other, { type: 'transfer.disputed', title: 'Transfer disputed', body: 'A dispute was raised on your transfer. An admin will review it.', data: { transferId: transfer.id, disputeId: d.rows[0].id } });
    await audit(db, { actorId: req.user.id, action: 'transfer.dispute', entityType: 'transfer', entityId: transfer.id, metadata: { disputeId: d.rows[0].id }, ip: clientIp(req) });
  });
  res.json({ transfer: await load(req.params.id, req.user.id) });
});

module.exports = router;
