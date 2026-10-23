const { notFound, forbidden, conflict } = require('../lib/errors');

/**
 * Load a device and lock its row for the rest of the transaction.
 * Locking the device row serialises every ownership-changing operation on it
 * (transfer completion, stolen approval, listing creation), so two requests
 * can't both act on a stale owner.
 */
async function lockDevice(db, deviceId) {
  const { rows } = await db.query('select * from devices where id = $1 for update', [deviceId]);
  if (!rows[0]) throw notFound('Device not found');
  return rows[0];
}

function assertOwner(device, user) {
  if (device.owner_id !== user.id) throw forbidden('You do not own this device');
}

function assertNotStolen(device) {
  if (device.registry_status === 'reported_stolen') {
    throw conflict('This device is reported stolen and cannot be sold or transferred', 'device_stolen');
  }
}

async function hasPendingTransfer(db, deviceId) {
  const { rows } = await db.query(`select 1 from ownership_transfers where device_id = $1 and status = 'pending'`, [deviceId]);
  return rows.length > 0;
}

async function hasPendingReport(db, deviceId) {
  const { rows } = await db.query(`select 1 from stolen_reports where device_id = $1 and status = 'pending'`, [deviceId]);
  return rows.length > 0;
}

// Shared SELECT for device cards: IMEIs, live listing, pending transfer/report flags.
const DEVICE_SUMMARY_SQL = `
  select d.id, d.owner_id, d.brand, d.model, d.storage_gb, d.color, d.registry_status, d.created_at,
    coalesce((select json_agg(json_build_object('imei', i.imei, 'slot', i.slot) order by i.slot)
              from device_imeis i where i.device_id = d.id), '[]') as imeis,
    (select json_build_object('id', l.id, 'status', l.status, 'price', l.price)
       from listings l where l.device_id = d.id and l.status in ('active','reserved') limit 1) as live_listing,
    (select t.id from ownership_transfers t where t.device_id = d.id and t.status = 'pending' limit 1) as pending_transfer_id,
    exists(select 1 from stolen_reports r where r.device_id = d.id and r.status = 'pending') as report_pending
  from devices d`;

function deviceDto(r) {
  return {
    id: r.id,
    brand: r.brand,
    model: r.model,
    storageGb: r.storage_gb,
    color: r.color,
    registryStatus: r.registry_status,
    imeis: r.imeis,
    liveListing: r.live_listing,
    pendingTransferId: r.pending_transfer_id,
    reportPending: r.report_pending,
    registeredAt: r.created_at,
  };
}

module.exports = { lockDevice, assertOwner, assertNotStolen, hasPendingTransfer, hasPendingReport, DEVICE_SUMMARY_SQL, deviceDto };
