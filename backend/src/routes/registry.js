const express = require('express');
const rateLimit = require('express-rate-limit');
const env = require('../config/env');
const { query } = require('../lib/db');
const { validateImei } = require('../lib/imei');
const { clientIp } = require('../lib/audit');
const { optionalAuth } = require('../middleware/auth');

const router = express.Router();

const DISCLAIMER =
  'This result comes from the DeviceTrust community registry only. It is NOT an official PTA/DIRBS check. '
  + 'To check official PTA status, SMS the IMEI to 8484 or use the PTA DIRBS website.';

const lookupLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: env.isTest ? 1000 : 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: { code: 'rate_limited', message: 'Too many lookups. Please wait a minute.' } },
});

/**
 * Public registry lookup. Returns only non-identifying device info — never the owner.
 * status: 'invalid' | 'not_found' | 'registered' | 'reported_stolen'
 */
router.get('/:imei', lookupLimiter, optionalAuth, async (req, res) => {
  const v = validateImei(req.params.imei);
  if (!v.valid) {
    return res.json({ imei: v.imei, status: 'invalid', reason: v.reason, source: 'devicetrust_registry', disclaimer: DISCLAIMER });
  }
  const { rows } = await query(
    `select d.id, d.brand, d.model, d.storage_gb, d.registry_status, d.created_at, d.owner_id,
            exists(select 1 from stolen_reports r where r.device_id = d.id and r.status = 'pending') as report_pending,
            (select count(*) from ownership_history h where h.device_id = d.id)::int as owner_count,
            (select l.id from listings l where l.device_id = d.id and l.status = 'active' limit 1) as active_listing_id
     from device_imeis i join devices d on d.id = i.device_id where i.imei = $1`,
    [v.imei],
  );
  const d = rows[0];
  const status = !d ? 'not_found' : d.registry_status;

  await query('insert into imei_lookups (imei, user_id, result, ip) values ($1, $2, $3, $4)', [v.imei, req.user?.id ?? null, status, clientIp(req)]);

  return res.json({
    imei: v.imei,
    status,
    source: 'devicetrust_registry',
    checkedAt: new Date().toISOString(),
    device: d ? {
      brand: d.brand,
      model: d.model,
      storageGb: d.storage_gb,
      registeredSince: d.created_at,
      ownerCount: d.owner_count,
      reportUnderReview: d.report_pending,
      activeListingId: d.active_listing_id,
      ownedByYou: !!req.user && req.user.id === d.owner_id,
    } : null,
    disclaimer: DISCLAIMER,
  });
});

module.exports = router;
