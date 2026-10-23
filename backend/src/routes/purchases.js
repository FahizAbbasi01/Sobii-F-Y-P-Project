const express = require('express');
const { z } = require('zod');
const { query, tx } = require('../lib/db');
const { audit, notify, clientIp } = require('../lib/audit');
const { conflict, notFound, forbidden } = require('../lib/errors');
const { validate } = require('../middleware/validate');
const { requireAuth } = require('../middleware/auth');
const { lockDevice, assertNotStolen, hasPendingTransfer } = require('../services/devices');
const { cancelTransfer } = require('../services/transfers');

const router = express.Router();
router.use(requireAuth);

const idParams = z.object({ id: z.uuid() });

const REQUEST_SQL = `
  select pr.*, l.title, l.price as listing_price, l.status as listing_status, l.seller_id, l.device_id,
         d.brand, d.model, d.storage_gb,
         b.full_name as buyer_name, b.city as buyer_city, s.full_name as seller_name,
         (select t.id from ownership_transfers t where t.purchase_request_id = pr.id order by t.created_at desc limit 1) as transfer_id,
         (select t.status from ownership_transfers t where t.purchase_request_id = pr.id order by t.created_at desc limit 1) as transfer_status
  from purchase_requests pr
  join listings l on l.id = pr.listing_id
  join devices d on d.id = l.device_id
  join users b on b.id = pr.buyer_id
  join users s on s.id = l.seller_id`;

function dto(r, userId) {
  return {
    id: r.id,
    status: r.status,
    offerPrice: r.offer_price,
    message: r.message,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
    role: r.buyer_id === userId ? 'buyer' : 'seller',
    listing: { id: r.listing_id, title: r.title, price: r.listing_price, status: r.listing_status },
    device: { id: r.device_id, brand: r.brand, model: r.model, storageGb: r.storage_gb },
    buyer: { id: r.buyer_id, name: r.buyer_name, city: r.buyer_city },
    seller: { id: r.seller_id, name: r.seller_name },
    transfer: r.transfer_id ? { id: r.transfer_id, status: r.transfer_status } : null,
  };
}

const createSchema = z.object({
  listingId: z.uuid(),
  offerPrice: z.coerce.number().positive().max(99999999).optional(),
  message: z.string().trim().max(500).optional().nullable(),
});

router.post('/', validate({ body: createSchema }), async (req, res) => {
  const b = req.body;
  const id = await tx(async (db) => {
    const l = (await db.query('select * from listings where id = $1', [b.listingId])).rows[0];
    if (!l) throw notFound('Listing not found');
    const device = await lockDevice(db, l.device_id);
    const listing = (await db.query('select * from listings where id = $1 for update', [l.id])).rows[0];
    if (listing.seller_id === req.user.id) throw forbidden('You cannot buy your own listing');
    if (listing.status !== 'active') throw conflict('This listing is no longer available', 'listing_unavailable');
    assertNotStolen(device);
    const { rows } = await db.query(
      `insert into purchase_requests (listing_id, buyer_id, offer_price, message) values ($1, $2, $3, $4) returning id`,
      [listing.id, req.user.id, b.offerPrice ?? listing.price, b.message || null],
    );
    await notify(db, listing.seller_id, {
      type: 'purchase.new', title: 'New purchase request',
      body: `${req.user.full_name} wants to buy your ${device.brand} ${device.model}.`,
      data: { purchaseRequestId: rows[0].id, listingId: listing.id },
    });
    await audit(db, { actorId: req.user.id, action: 'purchase.create', entityType: 'purchase_request', entityId: rows[0].id, metadata: { listingId: listing.id }, ip: clientIp(req) });
    return rows[0].id;
  });
  const { rows } = await query(`${REQUEST_SQL} where pr.id = $1`, [id]);
  res.status(201).json({ request: dto(rows[0], req.user.id) });
});

const listSchema = z.object({ role: z.enum(['buyer', 'seller', 'all']).default('all') });

router.get('/', validate({ query: listSchema }), async (req, res) => {
  const cond = { buyer: 'pr.buyer_id = $1', seller: 'l.seller_id = $1', all: '(pr.buyer_id = $1 or l.seller_id = $1)' }[req.q.role];
  const { rows } = await query(`${REQUEST_SQL} where ${cond} order by pr.created_at desc limit 200`, [req.user.id]);
  res.json({ requests: rows.map((r) => dto(r, req.user.id)) });
});

router.get('/:id', validate({ params: idParams }), async (req, res) => {
  const { rows } = await query(`${REQUEST_SQL} where pr.id = $1`, [req.params.id]);
  const r = rows[0];
  if (!r || (r.buyer_id !== req.user.id && r.seller_id !== req.user.id)) throw notFound('Request not found');
  res.json({ request: dto(r, req.user.id) });
});

/** Lock device → listing → request, in that order. */
async function lockRequest(db, id) {
  const peek = (await db.query(
    'select pr.id, l.device_id from purchase_requests pr join listings l on l.id = pr.listing_id where pr.id = $1', [id],
  )).rows[0];
  if (!peek) throw notFound('Request not found');
  const device = await lockDevice(db, peek.device_id);
  const request = (await db.query('select * from purchase_requests where id = $1 for update', [id])).rows[0];
  const listing = (await db.query('select * from listings where id = $1 for update', [request.listing_id])).rows[0];
  return { device, request, listing };
}

// Seller accepts → listing reserved + ownership transfer created (still needs both confirmations).
router.post('/:id/accept', validate({ params: idParams }), async (req, res) => {
  const transferId = await tx(async (db) => {
    const { device, request, listing } = await lockRequest(db, req.params.id);
    if (listing.seller_id !== req.user.id) throw forbidden('Only the seller can accept this request');
    if (request.status !== 'pending') throw conflict(`This request is already ${request.status}`);
    if (listing.status !== 'active') throw conflict('This listing is no longer active');
    if (device.owner_id !== req.user.id) throw conflict('You no longer own this device', 'ownership_changed');
    assertNotStolen(device);
    if (await hasPendingTransfer(db, device.id)) throw conflict('This device already has a transfer in progress', 'transfer_pending');

    await db.query(`update purchase_requests set status = 'accepted' where id = $1`, [request.id]);
    await db.query(`update listings set status = 'reserved' where id = $1`, [listing.id]);
    const t = await db.query(
      `insert into ownership_transfers (device_id, from_user_id, to_user_id, purchase_request_id) values ($1, $2, $3, $4) returning id`,
      [device.id, req.user.id, request.buyer_id, request.id],
    );
    await notify(db, request.buyer_id, {
      type: 'purchase.accepted', title: 'Request accepted',
      body: `The seller accepted your request for the ${device.brand} ${device.model}. Meet, inspect the phone, then confirm the transfer.`,
      data: { purchaseRequestId: request.id, transferId: t.rows[0].id },
    });
    await audit(db, { actorId: req.user.id, action: 'purchase.accept', entityType: 'purchase_request', entityId: request.id, metadata: { transferId: t.rows[0].id }, ip: clientIp(req) });
    return t.rows[0].id;
  });
  const { rows } = await query(`${REQUEST_SQL} where pr.id = $1`, [req.params.id]);
  res.json({ request: dto(rows[0], req.user.id), transferId });
});

router.post('/:id/reject', validate({ params: idParams }), async (req, res) => {
  await tx(async (db) => {
    const { request, listing } = await lockRequest(db, req.params.id);
    if (listing.seller_id !== req.user.id) throw forbidden('Only the seller can reject this request');
    if (request.status !== 'pending') throw conflict(`This request is already ${request.status}`);
    await db.query(`update purchase_requests set status = 'rejected' where id = $1`, [request.id]);
    await notify(db, request.buyer_id, { type: 'purchase.rejected', title: 'Request declined', body: `The seller declined your request for "${listing.title}".`, data: { purchaseRequestId: request.id } });
    await audit(db, { actorId: req.user.id, action: 'purchase.reject', entityType: 'purchase_request', entityId: request.id, ip: clientIp(req) });
  });
  res.json({ ok: true });
});

// Buyer withdraws. If already accepted, the pending transfer is cancelled and the listing re-opens.
router.post('/:id/cancel', validate({ params: idParams }), async (req, res) => {
  await tx(async (db) => {
    const { request, listing } = await lockRequest(db, req.params.id);
    if (request.buyer_id !== req.user.id) throw forbidden('Only the buyer can cancel this request');
    if (request.status === 'pending') {
      await db.query(`update purchase_requests set status = 'cancelled' where id = $1`, [request.id]);
      await audit(db, { actorId: req.user.id, action: 'purchase.cancel', entityType: 'purchase_request', entityId: request.id, ip: clientIp(req) });
    } else if (request.status === 'accepted') {
      const t = (await db.query(
        `select * from ownership_transfers where purchase_request_id = $1 and status = 'pending' for update`, [request.id],
      )).rows[0];
      if (t) await cancelTransfer(db, t, { actorId: req.user.id, reason: 'The buyer withdrew their purchase request.', ip: clientIp(req) });
      else throw conflict('This request can no longer be cancelled');
    } else {
      throw conflict(`This request is already ${request.status}`);
    }
    await notify(db, listing.seller_id, { type: 'purchase.cancelled', title: 'Request withdrawn', body: `A buyer withdrew their request for "${listing.title}".`, data: { purchaseRequestId: request.id } });
  });
  res.json({ ok: true });
});

module.exports = router;
