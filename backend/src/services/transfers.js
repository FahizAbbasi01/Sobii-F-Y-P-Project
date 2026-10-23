const { conflict, forbidden, notFound } = require('../lib/errors');
const { audit, notify } = require('../lib/audit');
const { lockDevice, assertNotStolen } = require('./devices');

/**
 * Lock order everywhere: device row → transfer row → listing/request rows.
 * Using one order avoids deadlocks between concurrent operations.
 */

async function lockTransfer(db, transferId) {
  // Read device_id without a lock, lock the device, then lock and re-read the transfer.
  const peek = await db.query('select device_id from ownership_transfers where id = $1', [transferId]);
  if (!peek.rows[0]) throw notFound('Transfer not found');
  const device = await lockDevice(db, peek.rows[0].device_id);
  const { rows } = await db.query('select * from ownership_transfers where id = $1 for update', [transferId]);
  return { device, transfer: rows[0] };
}

function assertParticipant(transfer, user) {
  if (transfer.from_user_id !== user.id && transfer.to_user_id !== user.id) throw forbidden('You are not part of this transfer');
}

/**
 * Called inside a transaction after a confirmation. Completes the transfer only
 * when BOTH parties have confirmed and the device state is still valid.
 */
async function completeIfReady(db, device, transfer, { actorId, ip }) {
  if (!transfer.seller_confirmed_at || !transfer.buyer_confirmed_at) return false;

  // Re-verify everything against the locked device row at completion time.
  if (device.owner_id !== transfer.from_user_id) throw conflict('The sender no longer owns this device', 'ownership_changed');
  assertNotStolen(device);

  await db.query(`update devices set owner_id = $2 where id = $1`, [device.id, transfer.to_user_id]);
  const closed = await db.query(
    `update ownership_history set released_at = now() where device_id = $1 and released_at is null and owner_id = $2`,
    [device.id, transfer.from_user_id],
  );
  if (closed.rowCount !== 1) throw conflict('Ownership record is inconsistent; contact support', 'ownership_inconsistent');
  await db.query(
    `insert into ownership_history (device_id, owner_id, acquired_via, transfer_id) values ($1, $2, 'transfer', $3)`,
    [device.id, transfer.to_user_id, transfer.id],
  );
  await db.query(`update ownership_transfers set status = 'completed', completed_at = now() where id = $1`, [transfer.id]);

  // Marketplace side effects.
  const live = await db.query(
    `update listings set status = 'sold' where device_id = $1 and status in ('active','reserved') returning id`,
    [device.id],
  );
  if (transfer.purchase_request_id) {
    await db.query(`update purchase_requests set status = 'completed' where id = $1`, [transfer.purchase_request_id]);
  }
  for (const l of live.rows) {
    const others = await db.query(
      `update purchase_requests set status = 'rejected' where listing_id = $1 and status = 'pending' returning buyer_id`,
      [l.id],
    );
    for (const o of others.rows) {
      await notify(db, o.buyer_id, { type: 'purchase.rejected', title: 'Listing sold', body: 'A phone you requested has been sold to another buyer.', data: { listingId: l.id } });
    }
  }

  const label = `${device.brand} ${device.model}`;
  await notify(db, transfer.to_user_id, { type: 'transfer.completed', title: 'Ownership transferred', body: `You are now the registered owner of the ${label}.`, data: { transferId: transfer.id, deviceId: device.id } });
  await notify(db, transfer.from_user_id, { type: 'transfer.completed', title: 'Transfer complete', body: `Ownership of the ${label} has been transferred.`, data: { transferId: transfer.id, deviceId: device.id } });
  await audit(db, { actorId, action: 'transfer.complete', entityType: 'transfer', entityId: transfer.id, metadata: { deviceId: device.id, from: transfer.from_user_id, to: transfer.to_user_id }, ip });
  return true;
}

/**
 * Cancels a pending/disputed transfer and puts its marketplace state back:
 * accepted purchase request → cancelled, reserved listing → active.
 */
async function cancelTransfer(db, transfer, { actorId, reason, ip }) {
  await db.query(`update ownership_transfers set status = 'cancelled', cancelled_by = $2 where id = $1`, [transfer.id, actorId]);
  if (transfer.purchase_request_id) {
    const pr = await db.query(
      `update purchase_requests set status = 'cancelled' where id = $1 and status = 'accepted' returning listing_id`,
      [transfer.purchase_request_id],
    );
    if (pr.rows[0]) {
      await db.query(`update listings set status = 'active' where id = $1 and status = 'reserved'`, [pr.rows[0].listing_id]);
    }
  }
  for (const uid of [transfer.from_user_id, transfer.to_user_id]) {
    if (uid === actorId) continue;
    await notify(db, uid, { type: 'transfer.cancelled', title: 'Transfer cancelled', body: reason || 'An ownership transfer you were part of was cancelled.', data: { transferId: transfer.id } });
  }
  await audit(db, { actorId, action: 'transfer.cancel', entityType: 'transfer', entityId: transfer.id, metadata: { reason: reason || null }, ip });
}

module.exports = { lockTransfer, assertParticipant, completeIfReady, cancelTransfer };
