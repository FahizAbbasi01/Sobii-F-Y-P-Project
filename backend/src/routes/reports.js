const express = require('express');
const { z } = require('zod');
const { query, tx } = require('../lib/db');
const { audit, clientIp } = require('../lib/audit');
const { conflict, badRequest } = require('../lib/errors');
const { validate } = require('../middleware/validate');
const { requireAuth } = require('../middleware/auth');
const { lockDevice, assertOwner } = require('../services/devices');
const { cancelTransfer } = require('../services/transfers');

const router = express.Router();
router.use(requireAuth);

const createSchema = z.object({
  deviceId: z.uuid(),
  incidentDate: z.iso.date(),
  location: z.string().trim().min(2).max(200),
  description: z.string().trim().min(10).max(2000),
  policeReportNumber: z.string().trim().max(50).optional().nullable(),
});

/**
 * Only the registered owner can report their device stolen. The device stays
 * 'registered' until an admin approves the report; meanwhile we take it off the
 * market and cancel any in-flight transfer so it can't change hands.
 */
router.post('/', validate({ body: createSchema }), async (req, res) => {
  const b = req.body;
  if (new Date(b.incidentDate) > new Date()) throw badRequest('Incident date cannot be in the future');
  const id = await tx(async (db) => {
    const device = await lockDevice(db, b.deviceId);
    assertOwner(device, req.user);
    if (device.registry_status === 'reported_stolen') throw conflict('This device is already marked as stolen');
    const { rows } = await db.query(
      `insert into stolen_reports (device_id, reporter_id, incident_date, location, description, police_report_number)
       values ($1, $2, $3, $4, $5, $6) returning id`,
      [device.id, req.user.id, b.incidentDate, b.location, b.description, b.policeReportNumber || null],
    );
    const transfers = await db.query(`select * from ownership_transfers where device_id = $1 and status in ('pending','disputed') for update`, [device.id]);
    for (const t of transfers.rows) {
      await cancelTransfer(db, t, { actorId: req.user.id, reason: 'The owner reported this device as stolen.', ip: clientIp(req) });
    }
    const live = await db.query(`update listings set status = 'withdrawn' where device_id = $1 and status in ('active','reserved') returning id`, [device.id]);
    for (const l of live.rows) {
      await db.query(`update purchase_requests set status = 'rejected' where listing_id = $1 and status in ('pending','accepted')`, [l.id]);
    }
    await audit(db, { actorId: req.user.id, action: 'report.create', entityType: 'stolen_report', entityId: rows[0].id, metadata: { deviceId: device.id }, ip: clientIp(req) });
    return rows[0].id;
  });
  const { rows } = await query(`select * from stolen_reports where id = $1`, [id]);
  res.status(201).json({ report: dto(rows[0]) });
});

function dto(r) {
  return {
    id: r.id,
    deviceId: r.device_id,
    device: r.brand ? { brand: r.brand, model: r.model } : undefined,
    incidentDate: r.incident_date,
    location: r.location,
    description: r.description,
    policeReportNumber: r.police_report_number,
    status: r.status,
    reviewNote: r.review_note,
    reviewedAt: r.reviewed_at,
    createdAt: r.created_at,
  };
}

router.get('/', async (req, res) => {
  const { rows } = await query(
    `select r.*, d.brand, d.model from stolen_reports r join devices d on d.id = r.device_id
     where r.reporter_id = $1 order by r.created_at desc`,
    [req.user.id],
  );
  res.json({ reports: rows.map(dto) });
});

module.exports = router;
