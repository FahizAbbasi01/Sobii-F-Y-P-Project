const express = require('express');
const { z } = require('zod');
const { query, tx } = require('../lib/db');
const { validateImei } = require('../lib/imei');
const { audit, clientIp } = require('../lib/audit');
const { badRequest, conflict, notFound, forbidden } = require('../lib/errors');
const { validate } = require('../middleware/validate');
const { requireAuth } = require('../middleware/auth');
const { DEVICE_SUMMARY_SQL, deviceDto, lockDevice, assertOwner, assertNotStolen } = require('../services/devices');

const router = express.Router();
router.use(requireAuth);

const imeiField = z.string().trim().max(20);
const idParams = z.object({ id: z.uuid() });

const createSchema = z.object({
  imei1: imeiField,
  imei2: imeiField.optional().nullable(),
  brand: z.string().trim().min(1).max(50),
  model: z.string().trim().min(1).max(80),
  storageGb: z.coerce.number().int().min(1).max(4096).optional().nullable(),
  color: z.string().trim().max(30).optional().nullable(),
});

router.post('/', validate({ body: createSchema }), async (req, res) => {
  const b = req.body;
  const one = validateImei(b.imei1);
  if (!one.valid) throw badRequest(`IMEI 1: ${one.reason}`);
  const imeis = [one.imei];
  if (b.imei2) {
    const two = validateImei(b.imei2);
    if (!two.valid) throw badRequest(`IMEI 2: ${two.reason}`);
    if (two.imei === one.imei) throw badRequest('IMEI 1 and IMEI 2 must be different');
    imeis.push(two.imei);
  }

  const device = await tx(async (db) => {
    const dup = await db.query('select imei from device_imeis where imei = any($1)', [imeis]);
    if (dup.rows.length) throw conflict(`IMEI ${dup.rows[0].imei} is already registered in DeviceTrust`, 'imei_taken');

    const { rows } = await db.query(
      `insert into devices (owner_id, brand, model, storage_gb, color) values ($1, $2, $3, $4, $5) returning id`,
      [req.user.id, b.brand, b.model, b.storageGb ?? null, b.color ?? null],
    );
    const id = rows[0].id;
    for (let i = 0; i < imeis.length; i += 1) {
      await db.query('insert into device_imeis (imei, device_id, slot) values ($1, $2, $3)', [imeis[i], id, i + 1]);
    }
    await db.query(
      `insert into ownership_history (device_id, owner_id, acquired_via) values ($1, $2, 'registration')`,
      [id, req.user.id],
    );
    await audit(db, { actorId: req.user.id, action: 'device.register', entityType: 'device', entityId: id, metadata: { imeis }, ip: clientIp(req) });
    const full = await db.query(`${DEVICE_SUMMARY_SQL} where d.id = $1`, [id]);
    return deviceDto(full.rows[0]);
  });
  res.status(201).json({ device });
});

router.get('/', async (req, res) => {
  const { rows } = await query(`${DEVICE_SUMMARY_SQL} where d.owner_id = $1 order by d.created_at desc`, [req.user.id]);
  res.json({ devices: rows.map(deviceDto) });
});

router.get('/:id', validate({ params: idParams }), async (req, res) => {
  const { rows } = await query(`${DEVICE_SUMMARY_SQL} where d.id = $1`, [req.params.id]);
  const d = rows[0];
  if (!d) throw notFound('Device not found');
  if (d.owner_id !== req.user.id && req.user.role !== 'admin') throw forbidden('You do not own this device');
  const history = await query(
    `select h.acquired_via, h.acquired_at, h.released_at, h.owner_id = $2 as is_you,
            -- Only show other owners' first name + initial to protect privacy.
            split_part(u.full_name, ' ', 1) || coalesce(' ' || left(nullif(split_part(u.full_name, ' ', 2), ''), 1) || '.', '') as owner_name
     from ownership_history h join users u on u.id = h.owner_id
     where h.device_id = $1 order by h.acquired_at`,
    [d.id, req.user.id],
  );
  res.json({
    device: deviceDto(d),
    ownershipHistory: history.rows.map((h) => ({
      ownerName: h.owner_name, isYou: h.is_you, acquiredVia: h.acquired_via, acquiredAt: h.acquired_at, releasedAt: h.released_at,
    })),
  });
});

const updateSchema = z.object({
  storageGb: z.coerce.number().int().min(1).max(4096).optional().nullable(),
  color: z.string().trim().max(30).optional().nullable(),
}).strict();

// Brand/model/IMEI are identity fields and cannot be edited after registration.
router.patch('/:id', validate({ params: idParams, body: updateSchema }), async (req, res) => {
  const device = await tx(async (db) => {
    const d = await lockDevice(db, req.params.id);
    assertOwner(d, req.user);
    assertNotStolen(d);
    await db.query(
      `update devices set storage_gb = case when $2::boolean then $3 else storage_gb end,
                          color = case when $4::boolean then $5 else color end where id = $1`,
      [d.id, 'storageGb' in req.body, req.body.storageGb ?? null, 'color' in req.body, req.body.color ?? null],
    );
    await audit(db, { actorId: req.user.id, action: 'device.update', entityType: 'device', entityId: d.id, metadata: req.body, ip: clientIp(req) });
    const full = await db.query(`${DEVICE_SUMMARY_SQL} where d.id = $1`, [d.id]);
    return deviceDto(full.rows[0]);
  });
  res.json({ device });
});

module.exports = router;
