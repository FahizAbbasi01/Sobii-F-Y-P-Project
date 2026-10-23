const express = require('express');
const { z } = require('zod');
const { query, tx } = require('../lib/db');
const { audit, clientIp } = require('../lib/audit');
const { forbidden, notFound } = require('../lib/errors');
const { validate } = require('../middleware/validate');
const { requireAuth } = require('../middleware/auth');
const storage = require('../services/storage');

const router = express.Router();
router.use(requireAuth);

const KINDS = ['purchase_receipt', 'box_photo', 'police_report', 'cnic', 'other'];
const bodySchema = z.object({
  kind: z.enum(KINDS),
  deviceId: z.uuid().optional(),
  stolenReportId: z.uuid().optional(),
});

// Upload a supporting document (receipt, box photo, police report). Stored in a private bucket.
router.post('/', storage.upload.single('file'), validate({ body: bodySchema }), async (req, res) => {
  const { mime } = storage.checkFile(req.file, ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);
  const b = req.body;
  if (b.deviceId) {
    const d = (await query('select owner_id from devices where id = $1', [b.deviceId])).rows[0];
    if (!d) throw notFound('Device not found');
    if (d.owner_id !== req.user.id) throw forbidden('You do not own this device');
  }
  if (b.stolenReportId) {
    const r = (await query('select reporter_id from stolen_reports where id = $1', [b.stolenReportId])).rows[0];
    if (!r) throw notFound('Report not found');
    if (r.reporter_id !== req.user.id) throw forbidden('This is not your report');
  }
  const key = await storage.put(`documents/${req.user.id}`, req.file.buffer, mime);
  const doc = await tx(async (db) => {
    const { rows } = await db.query(
      `insert into documents (owner_id, device_id, stolen_report_id, kind, storage_path, mime_type, size_bytes)
       values ($1, $2, $3, $4, $5, $6, $7) returning id, kind, status, created_at`,
      [req.user.id, b.deviceId || null, b.stolenReportId || null, b.kind, key, mime, req.file.size],
    );
    await audit(db, { actorId: req.user.id, action: 'document.upload', entityType: 'document', entityId: rows[0].id, metadata: { kind: b.kind }, ip: clientIp(req) });
    return rows[0];
  });
  res.status(201).json({ document: { id: doc.id, kind: doc.kind, status: doc.status, createdAt: doc.created_at } });
});

router.get('/', async (req, res) => {
  const { rows } = await query(
    `select id, kind, status, device_id, stolen_report_id, review_note, created_at from documents where owner_id = $1 order by created_at desc`,
    [req.user.id],
  );
  res.json({
    documents: rows.map((r) => ({
      id: r.id, kind: r.kind, status: r.status, deviceId: r.device_id, stolenReportId: r.stolen_report_id, reviewNote: r.review_note, createdAt: r.created_at,
    })),
  });
});

module.exports = router;
