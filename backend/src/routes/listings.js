const express = require('express');
const { z } = require('zod');
const { query, tx } = require('../lib/db');
const { audit, clientIp } = require('../lib/audit');
const { conflict, notFound, forbidden, badRequest } = require('../lib/errors');
const { validate } = require('../middleware/validate');
const { requireAuth, optionalAuth } = require('../middleware/auth');
const { lockDevice, assertOwner, assertNotStolen, hasPendingTransfer, hasPendingReport } = require('../services/devices');
const storage = require('../services/storage');

const router = express.Router();

const CONDITIONS = ['new', 'like_new', 'good', 'fair', 'poor'];
const idParams = z.object({ id: z.uuid() });

const LISTING_SQL = `
  select l.*, d.brand, d.model, d.storage_gb, d.color, d.registry_status,
         s.full_name as seller_name, s.city as seller_city, s.created_at as seller_since,
         (select count(*) from listings x where x.seller_id = l.seller_id and x.status = 'sold')::int as seller_sold_count,
         (select right(i.imei, 4) from device_imeis i where i.device_id = d.id and i.slot = 1) as imei_last4,
         (select count(*) from ownership_history h where h.device_id = d.id)::int as owner_count,
         coalesce((select json_agg(json_build_object('id', im.id, 'path', im.storage_path) order by im.position, im.created_at)
                   from listing_images im where im.listing_id = l.id), '[]') as images
  from listings l
  join devices d on d.id = l.device_id
  join users s on s.id = l.seller_id`;

async function listingDto(r, { detail = false } = {}) {
  const imageUrls = await Promise.all(r.images.map(async (im) => ({ id: im.id, url: await storage.signedUrl(im.path) })));
  const dto = {
    id: r.id,
    title: r.title,
    price: r.price,
    condition: r.condition,
    city: r.city,
    status: r.status,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
    images: detail ? imageUrls : imageUrls.slice(0, 1),
    device: {
      id: r.device_id, brand: r.brand, model: r.model, storageGb: r.storage_gb, color: r.color,
      registryStatus: r.registry_status, imeiLast4: r.imei_last4, ownerCount: r.owner_count,
    },
    seller: { id: r.seller_id, name: r.seller_name, city: r.seller_city, memberSince: r.seller_since, soldCount: r.seller_sold_count },
  };
  if (detail) dto.description = r.description;
  return dto;
}

// ---------- Browse (public) ----------
const browseSchema = z.object({
  q: z.string().trim().max(80).optional(),
  brand: z.string().trim().max(50).optional(),
  condition: z.enum(CONDITIONS).optional(),
  city: z.string().trim().max(60).optional(),
  minPrice: z.coerce.number().min(0).optional(),
  maxPrice: z.coerce.number().min(0).optional(),
  minStorage: z.coerce.number().int().min(0).optional(),
  sort: z.enum(['newest', 'price_asc', 'price_desc', 'oldest']).default('newest'),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

const SORTS = {
  newest: 'l.created_at desc, l.id',
  oldest: 'l.created_at asc, l.id',
  price_asc: 'l.price asc, l.created_at desc',
  price_desc: 'l.price desc, l.created_at desc',
};

router.get('/', optionalAuth, validate({ query: browseSchema }), async (req, res) => {
  const f = req.q;
  const where = [`l.status = 'active'`, `d.registry_status = 'registered'`];
  const params = [];
  const add = (sql, value) => { params.push(value); where.push(sql.replace('?', `$${params.length}`)); };
  if (f.q) {
    const like = `%${f.q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
    params.push(like);
    const p = `$${params.length}`;
    where.push(`(l.title ilike ${p} or d.brand ilike ${p} or d.model ilike ${p} or (d.brand || ' ' || d.model) ilike ${p})`);
  }
  if (f.brand) add('d.brand ilike ?', f.brand);
  if (f.condition) add('l.condition = ?', f.condition);
  if (f.city) add('l.city ilike ?', f.city);
  if (f.minPrice !== undefined) add('l.price >= ?', f.minPrice);
  if (f.maxPrice !== undefined) add('l.price <= ?', f.maxPrice);
  if (f.minStorage !== undefined) add('d.storage_gb >= ?', f.minStorage);
  if (f.minPrice !== undefined && f.maxPrice !== undefined && f.minPrice > f.maxPrice) throw badRequest('minPrice cannot exceed maxPrice');

  const whereSql = where.join(' and ');
  const offset = (f.page - 1) * f.limit;
  const [list, count] = await Promise.all([
    query(`${LISTING_SQL} where ${whereSql} order by ${SORTS[f.sort]} limit ${f.limit} offset ${offset}`, params),
    query(`select count(*)::int as n from listings l join devices d on d.id = l.device_id where ${whereSql}`, params),
  ]);
  res.json({
    listings: await Promise.all(list.rows.map((r) => listingDto(r))),
    page: f.page,
    limit: f.limit,
    total: count.rows[0].n,
  });
});

router.get('/brands', async (_req, res) => {
  const { rows } = await query(
    `select d.brand, count(*)::int as n from listings l join devices d on d.id = l.device_id
     where l.status = 'active' group by d.brand order by n desc, d.brand limit 30`,
  );
  res.json({ brands: rows.map((r) => ({ name: r.brand, count: r.n })) });
});

router.get('/mine', requireAuth, async (req, res) => {
  const { rows } = await query(
    `${LISTING_SQL} where l.seller_id = $1 order by l.created_at desc`,
    [req.user.id],
  );
  const pending = await query(
    `select listing_id, count(*)::int as n from purchase_requests
     where status = 'pending' and listing_id = any($1) group by listing_id`,
    [rows.map((r) => r.id)],
  );
  const counts = Object.fromEntries(pending.rows.map((p) => [p.listing_id, p.n]));
  res.json({
    listings: await Promise.all(rows.map(async (r) => ({ ...(await listingDto(r)), pendingRequests: counts[r.id] || 0 }))),
  });
});

router.get('/:id', optionalAuth, validate({ params: idParams }), async (req, res) => {
  const { rows } = await query(`${LISTING_SQL} where l.id = $1`, [req.params.id]);
  const r = rows[0];
  const isSeller = req.user && r && req.user.id === r.seller_id;
  const isAdmin = req.user && req.user.role === 'admin';
  // Withdrawn/removed listings are only visible to the seller and admins.
  if (!r || (['withdrawn', 'removed'].includes(r.status) && !isSeller && !isAdmin)) throw notFound('Listing not found');
  const listing = await listingDto(r, { detail: true });
  let myRequest = null;
  if (req.user && !isSeller) {
    const pr = await query(
      `select id, status, offer_price, created_at from purchase_requests
       where listing_id = $1 and buyer_id = $2 order by created_at desc limit 1`,
      [r.id, req.user.id],
    );
    if (pr.rows[0]) myRequest = { id: pr.rows[0].id, status: pr.rows[0].status, offerPrice: pr.rows[0].offer_price };
  }
  res.json({ listing, isSeller: !!isSeller, myRequest });
});

// ---------- Create / edit (seller) ----------
const createSchema = z.object({
  deviceId: z.uuid(),
  title: z.string().trim().min(3).max(120),
  description: z.string().trim().max(2000).optional().nullable(),
  price: z.coerce.number().positive().max(99999999),
  condition: z.enum(CONDITIONS),
  city: z.string().trim().min(2).max(60),
});

router.post('/', requireAuth, validate({ body: createSchema }), async (req, res) => {
  const b = req.body;
  const id = await tx(async (db) => {
    const device = await lockDevice(db, b.deviceId);
    assertOwner(device, req.user);
    assertNotStolen(device);
    if (await hasPendingTransfer(db, device.id)) throw conflict('This device has a transfer in progress', 'transfer_pending');
    if (await hasPendingReport(db, device.id)) throw conflict('This device has a stolen report under review', 'report_pending');
    const { rows } = await db.query(
      `insert into listings (device_id, seller_id, title, description, price, condition, city)
       values ($1, $2, $3, $4, $5, $6, $7) returning id`,
      [device.id, req.user.id, b.title, b.description || null, b.price, b.condition, b.city],
    );
    await audit(db, { actorId: req.user.id, action: 'listing.create', entityType: 'listing', entityId: rows[0].id, metadata: { deviceId: device.id, price: b.price }, ip: clientIp(req) });
    return rows[0].id;
  });
  const { rows } = await query(`${LISTING_SQL} where l.id = $1`, [id]);
  res.status(201).json({ listing: await listingDto(rows[0], { detail: true }) });
});

async function lockOwnListing(db, id, user) {
  const { rows } = await db.query('select * from listings where id = $1 for update', [id]);
  const l = rows[0];
  if (!l) throw notFound('Listing not found');
  if (l.seller_id !== user.id) throw forbidden('This is not your listing');
  return l;
}

const updateSchema = z.object({
  title: z.string().trim().min(3).max(120).optional(),
  description: z.string().trim().max(2000).optional().nullable(),
  price: z.coerce.number().positive().max(99999999).optional(),
  condition: z.enum(CONDITIONS).optional(),
  city: z.string().trim().min(2).max(60).optional(),
}).strict();

router.patch('/:id', requireAuth, validate({ params: idParams, body: updateSchema }), async (req, res) => {
  const b = req.body;
  await tx(async (db) => {
    const l = await lockOwnListing(db, req.params.id, req.user);
    if (l.status !== 'active') throw conflict('Only active listings can be edited');
    await db.query(
      `update listings set title = coalesce($2, title),
         description = case when $3::boolean then $4 else description end,
         price = coalesce($5, price), condition = coalesce($6, condition), city = coalesce($7, city)
       where id = $1`,
      [l.id, b.title ?? null, 'description' in b, b.description ?? null, b.price ?? null, b.condition ?? null, b.city ?? null],
    );
    await audit(db, { actorId: req.user.id, action: 'listing.update', entityType: 'listing', entityId: l.id, metadata: b, ip: clientIp(req) });
  });
  const { rows } = await query(`${LISTING_SQL} where l.id = $1`, [req.params.id]);
  res.json({ listing: await listingDto(rows[0], { detail: true }) });
});

router.post('/:id/withdraw', requireAuth, validate({ params: idParams }), async (req, res) => {
  await tx(async (db) => {
    const l = await lockOwnListing(db, req.params.id, req.user);
    if (l.status !== 'active') throw conflict('Only active listings can be withdrawn. Cancel the pending transfer first.');
    await db.query(`update listings set status = 'withdrawn' where id = $1`, [l.id]);
    await db.query(`update purchase_requests set status = 'rejected' where listing_id = $1 and status = 'pending'`, [l.id]);
    await audit(db, { actorId: req.user.id, action: 'listing.withdraw', entityType: 'listing', entityId: l.id, ip: clientIp(req) });
  });
  res.json({ ok: true });
});

// ---------- Images ----------
router.post('/:id/images', requireAuth, storage.upload.array('images', 6), validate({ params: idParams }), async (req, res) => {
  const files = req.files || [];
  if (!files.length) throw badRequest('Attach at least one image (field name "images")');
  const checked = files.map((f) => ({ f, ...storage.checkFile(f, ['image/jpeg', 'image/png', 'image/webp']) }));
  const result = await tx(async (db) => {
    const l = await lockOwnListing(db, req.params.id, req.user);
    if (!['active', 'reserved'].includes(l.status)) throw conflict('Cannot add images to this listing');
    const existing = await db.query('select count(*)::int as n from listing_images where listing_id = $1', [l.id]);
    if (existing.rows[0].n + checked.length > 6) throw badRequest('A listing can have at most 6 images');
    const added = [];
    for (let i = 0; i < checked.length; i += 1) {
      const key = await storage.put(`listings/${l.id}`, checked[i].f.buffer, checked[i].mime);
      const { rows } = await db.query(
        'insert into listing_images (listing_id, storage_path, position) values ($1, $2, $3) returning id',
        [l.id, key, existing.rows[0].n + i],
      );
      added.push({ id: rows[0].id, url: await storage.signedUrl(key) });
    }
    return added;
  });
  res.status(201).json({ images: result });
});

router.delete('/:id/images/:imageId', requireAuth, validate({ params: z.object({ id: z.uuid(), imageId: z.uuid() }) }), async (req, res) => {
  const key = await tx(async (db) => {
    await lockOwnListing(db, req.params.id, req.user);
    const { rows } = await db.query('delete from listing_images where id = $1 and listing_id = $2 returning storage_path', [req.params.imageId, req.params.id]);
    if (!rows[0]) throw notFound('Image not found');
    return rows[0].storage_path;
  });
  await storage.remove(key).catch(() => {});
  res.status(204).end();
});

module.exports = router;
module.exports.LISTING_SQL = LISTING_SQL;
module.exports.listingDto = listingDto;
