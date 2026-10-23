const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

const { api, auth } = h;

before(h.resetDb);
after(() => h.pool.end());

describe('auth & roles', () => {
  test('client cannot self-assign admin role at registration', async () => {
    const res = await api().post('/api/v1/auth/register')
      .send({ email: 'sneaky@example.com', password: 'Passw0rd!', fullName: 'Sneaky User', role: 'admin' });
    assert.equal(res.status, 201);
    assert.equal(res.body.user.role, 'user');
    const admin = await api().get('/api/v1/admin/stats').set({ Authorization: `Bearer ${res.body.accessToken}` });
    assert.equal(admin.status, 403);
  });

  test('requests without/with a forged token are rejected', async () => {
    assert.equal((await api().get('/api/v1/devices')).status, 401);
    const forged = await api().get('/api/v1/devices').set({ Authorization: 'Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.' });
    assert.equal(forged.status, 401);
  });

  test('wrong password and unknown email give the same error', async () => {
    const u = await h.registerUser('Login');
    const a = await api().post('/api/v1/auth/login').send({ email: u.email, password: 'WrongPass1' });
    const b = await api().post('/api/v1/auth/login').send({ email: 'nobody@example.com', password: 'WrongPass1' });
    assert.equal(a.status, 401);
    assert.equal(b.status, 401);
    assert.equal(a.body.error.message, b.body.error.message);
  });

  test('refresh tokens rotate and cannot be reused', async () => {
    const u = await h.registerUser('Refresh');
    const first = await api().post('/api/v1/auth/refresh').send({ refreshToken: u.refreshToken });
    assert.equal(first.status, 200);
    const reuse = await api().post('/api/v1/auth/refresh').send({ refreshToken: u.refreshToken });
    assert.equal(reuse.status, 401);
  });

  test('suspended user loses access immediately, even with a valid token', async () => {
    const admin = await h.makeAdmin(await h.registerUser('Admin'));
    const u = await h.registerUser('Bad');
    assert.equal((await api().get('/api/v1/devices').set(auth(u))).status, 200);
    const s = await api().post(`/api/v1/admin/users/${u.id}/status`).set(auth(admin)).send({ status: 'suspended' });
    assert.equal(s.status, 200);
    assert.equal((await api().get('/api/v1/devices').set(auth(u))).status, 403);
  });
});

describe('devices & registry', () => {
  test('invalid IMEI rejected; duplicate IMEI rejected, including across slots', async () => {
    const a = await h.registerUser('Alice');
    const b = await h.registerUser('Bob');
    const bad = await api().post('/api/v1/devices').set(auth(a)).send({ imei1: '490154203237519', brand: 'X', model: 'Y' });
    assert.equal(bad.status, 400);

    const imei = h.makeImei();
    const ok = await api().post('/api/v1/devices').set(auth(a)).send({ imei1: imei, brand: 'Apple', model: 'iPhone 13' });
    assert.equal(ok.status, 201);
    const dup = await api().post('/api/v1/devices').set(auth(b)).send({ imei1: imei, brand: 'Apple', model: 'iPhone 13' });
    assert.equal(dup.status, 409);
    const dupSlot2 = await api().post('/api/v1/devices').set(auth(b)).send({ imei1: h.makeImei(), imei2: imei, brand: 'Apple', model: 'iPhone 13' });
    assert.equal(dupSlot2.status, 409);
  });

  test('registry lookup: invalid / not_found / registered, never leaks owner identity', async () => {
    const a = await h.registerUser('Owner');
    const d = await h.registerDevice(a);
    const imei = d.imeis[0].imei;
    assert.equal((await api().get('/api/v1/registry/123')).body.status, 'invalid');
    assert.equal((await api().get(`/api/v1/registry/${h.makeImei()}`)).body.status, 'not_found');
    const r = await api().get(`/api/v1/registry/${imei}`);
    assert.equal(r.body.status, 'registered');
    assert.match(r.body.disclaimer, /NOT an official PTA/);
    const text = JSON.stringify(r.body);
    assert.ok(!text.includes(a.email) && !text.includes(a.id) && !text.includes('Owner Tester'));
  });

  test("users cannot view or edit someone else's device", async () => {
    const a = await h.registerUser('A');
    const b = await h.registerUser('B');
    const d = await h.registerDevice(a);
    assert.equal((await api().get(`/api/v1/devices/${d.id}`).set(auth(b))).status, 403);
    assert.equal((await api().patch(`/api/v1/devices/${d.id}`).set(auth(b)).send({ color: 'Red' })).status, 403);
  });
});

describe('marketplace', () => {
  test("cannot list a device you don't own, or list the same device twice", async () => {
    const a = await h.registerUser('Seller');
    const b = await h.registerUser('Other');
    const d = await h.registerDevice(a);
    const steal = await api().post('/api/v1/listings').set(auth(b))
      .send({ deviceId: d.id, title: 'Not mine', price: 1000, condition: 'good', city: 'Lahore' });
    assert.equal(steal.status, 403);
    await h.createListing(a, d);
    const twice = await api().post('/api/v1/listings').set(auth(a))
      .send({ deviceId: d.id, title: 'Again', price: 1000, condition: 'good', city: 'Lahore' });
    assert.equal(twice.status, 409);
  });

  test('search, filter and sort return only active listings', async () => {
    const a = await h.registerUser('Searcher');
    const d1 = await h.registerDevice(a, { brand: 'Xiaomi', model: 'Redmi Note 12' });
    const d2 = await h.registerDevice(a, { brand: 'Xiaomi', model: 'Redmi Note 13' });
    await h.createListing(a, d1, { title: 'Redmi Note 12 clean', price: 40000 });
    const l2 = await h.createListing(a, d2, { title: 'Redmi Note 13 PTA', price: 55000 });
    await api().post(`/api/v1/listings/${l2.id}/withdraw`).set(auth(a));
    const res = await api().get('/api/v1/listings?q=redmi&sort=price_asc&maxPrice=60000');
    assert.equal(res.status, 200);
    assert.equal(res.body.listings.length, 1);
    assert.equal(res.body.listings[0].title, 'Redmi Note 12 clean');
  });

  test("buyer cannot request own listing; duplicate open request blocked; non-seller can't accept", async () => {
    const s = await h.registerUser('S');
    const b = await h.registerUser('Buyer');
    const x = await h.registerUser('Intruder');
    const l = await h.createListing(s, await h.registerDevice(s));
    assert.equal((await api().post('/api/v1/purchase-requests').set(auth(s)).send({ listingId: l.id })).status, 403);
    const r = await api().post('/api/v1/purchase-requests').set(auth(b)).send({ listingId: l.id });
    assert.equal(r.status, 201);
    assert.equal((await api().post('/api/v1/purchase-requests').set(auth(b)).send({ listingId: l.id })).status, 409);
    assert.equal((await api().post(`/api/v1/purchase-requests/${r.body.request.id}/accept`).set(auth(x))).status, 403);
    assert.equal((await api().post(`/api/v1/purchase-requests/${r.body.request.id}/accept`).set(auth(b))).status, 403);
  });
});

describe('ownership transfer', () => {
  test('ownership changes only after BOTH confirmations; history and listing update', async () => {
    const seller = await h.registerUser('Seller');
    const buyer = await h.registerUser('Buyer');
    const other = await h.registerUser('Other');
    const third = await h.registerUser('Third');
    const device = await h.registerDevice(seller);
    const listing = await h.createListing(seller, device);

    const r1 = await api().post('/api/v1/purchase-requests').set(auth(buyer)).send({ listingId: listing.id, offerPrice: 140000 });
    const r2 = await api().post('/api/v1/purchase-requests').set(auth(other)).send({ listingId: listing.id });
    const acc = await api().post(`/api/v1/purchase-requests/${r1.body.request.id}/accept`).set(auth(seller));
    assert.equal(acc.status, 200);
    const tid = acc.body.transferId;

    // Listing is reserved, hidden from browse.
    const browse = await api().get('/api/v1/listings');
    assert.ok(!browse.body.listings.some((l) => l.id === listing.id));

    // An outsider cannot confirm or even see the transfer.
    assert.equal((await api().post(`/api/v1/transfers/${tid}/confirm`).set(auth(third))).status, 403);

    const c1 = await api().post(`/api/v1/transfers/${tid}/confirm`).set(auth(seller));
    assert.equal(c1.body.completed, false);
    assert.equal((await api().get(`/api/v1/devices/${device.id}`).set(auth(seller))).status, 200, 'seller still owns it after one confirmation');
    assert.equal((await api().post(`/api/v1/transfers/${tid}/confirm`).set(auth(seller))).status, 409, 'double confirm blocked');

    const c2 = await api().post(`/api/v1/transfers/${tid}/confirm`).set(auth(buyer));
    assert.equal(c2.status, 200);
    assert.equal(c2.body.completed, true);

    const mine = await api().get(`/api/v1/devices/${device.id}`).set(auth(buyer));
    assert.equal(mine.status, 200);
    assert.equal(mine.body.ownershipHistory.length, 2);
    assert.equal(mine.body.ownershipHistory[0].releasedAt !== null, true);
    assert.equal((await api().get(`/api/v1/devices/${device.id}`).set(auth(seller))).status, 403);
    assert.equal((await api().get(`/api/v1/listings/${listing.id}`)).body.listing.status, 'sold');
    const otherReq = await api().get(`/api/v1/purchase-requests/${r2.body.request.id}`).set(auth(other));
    assert.equal(otherReq.body.request.status, 'rejected');

    const actions = (await h.pool.query(`select action from audit_logs where entity_id = $1`, [tid])).rows.map((r) => r.action);
    assert.ok(actions.includes('transfer.complete'));
  });

  test('accepting two requests at the same time: only one wins', async () => {
    const seller = await h.registerUser('Race');
    const b1 = await h.registerUser('B1');
    const b2 = await h.registerUser('B2');
    const l = await h.createListing(seller, await h.registerDevice(seller));
    const r1 = await api().post('/api/v1/purchase-requests').set(auth(b1)).send({ listingId: l.id });
    const r2 = await api().post('/api/v1/purchase-requests').set(auth(b2)).send({ listingId: l.id });
    const [x, y] = await Promise.all([
      api().post(`/api/v1/purchase-requests/${r1.body.request.id}/accept`).set(auth(seller)),
      api().post(`/api/v1/purchase-requests/${r2.body.request.id}/accept`).set(auth(seller)),
    ]);
    assert.deepEqual([x.status, y.status].sort(), [200, 409]);
    const { rows } = await h.pool.query(`select count(*)::int as n from ownership_transfers where status = 'pending'
      and device_id = (select device_id from listings where id = $1)`, [l.id]);
    assert.equal(rows[0].n, 1);
  });

  test("direct transfer: owner only, no duplicate active transfer, buyer can't confirm for seller", async () => {
    const a = await h.registerUser('Giver');
    const b = await h.registerUser('Getter');
    const c = await h.registerUser('Thief');
    const d = await h.registerDevice(a);
    assert.equal((await api().post('/api/v1/transfers').set(auth(c)).send({ deviceId: d.id, recipientEmail: c.email })).status, 403);
    const t = await api().post('/api/v1/transfers').set(auth(a)).send({ deviceId: d.id, recipientEmail: b.email });
    assert.equal(t.status, 201);
    assert.equal((await api().post('/api/v1/transfers').set(auth(a)).send({ deviceId: d.id, recipientEmail: c.email })).status, 409);
    const c1 = await api().post(`/api/v1/transfers/${t.body.transfer.id}/confirm`).set(auth(b));
    assert.equal(c1.body.completed, false, 'recipient confirmation alone must not transfer');
    assert.equal((await api().post(`/api/v1/transfers/${t.body.transfer.id}/confirm`).set(auth(b))).status, 409);
    const { rows } = await h.pool.query('select owner_id from devices where id = $1', [d.id]);
    assert.equal(rows[0].owner_id, a.id);
  });

  test('cancelling an accepted purchase re-opens the listing', async () => {
    const s = await h.registerUser('S2');
    const b = await h.registerUser('B3');
    const l = await h.createListing(s, await h.registerDevice(s));
    const r = await api().post('/api/v1/purchase-requests').set(auth(b)).send({ listingId: l.id });
    const acc = await api().post(`/api/v1/purchase-requests/${r.body.request.id}/accept`).set(auth(s));
    const cancel = await api().post(`/api/v1/transfers/${acc.body.transferId}/cancel`).set(auth(b));
    assert.equal(cancel.status, 200);
    assert.equal((await api().get(`/api/v1/listings/${l.id}`)).body.listing.status, 'active');
  });
});

describe('stolen reports', () => {
  test('only the owner can report; admin approval flags the device and blocks the market', async () => {
    const owner = await h.registerUser('Victim');
    const stranger = await h.registerUser('Stranger');
    const buyer = await h.registerUser('Buyer');
    const admin = await h.makeAdmin(await h.registerUser('Mod'));
    const d = await h.registerDevice(owner);
    const l = await h.createListing(owner, d);
    await api().post('/api/v1/purchase-requests').set(auth(buyer)).send({ listingId: l.id });

    const body = { deviceId: d.id, incidentDate: '2026-10-01', location: 'Saddar, Rawalpindi', description: 'Snatched at gunpoint near the bus stop' };
    assert.equal((await api().post('/api/v1/stolen-reports').set(auth(stranger)).send(body)).status, 403);
    const rep = await api().post('/api/v1/stolen-reports').set(auth(owner)).send(body);
    assert.equal(rep.status, 201);
    assert.equal(rep.body.report.status, 'pending');
    assert.equal((await api().post('/api/v1/stolen-reports').set(auth(owner)).send(body)).status, 409);

    // Non-admin cannot approve.
    assert.equal((await api().post(`/api/v1/admin/reports/${rep.body.report.id}/approve`).set(auth(owner)).send({})).status, 403);
    const ok = await api().post(`/api/v1/admin/reports/${rep.body.report.id}/approve`).set(auth(admin)).send({ note: 'FIR verified' });
    assert.equal(ok.status, 200);

    const imei = d.imeis[0].imei;
    assert.equal((await api().get(`/api/v1/registry/${imei}`)).body.status, 'reported_stolen');
    const relist = await api().post('/api/v1/listings').set(auth(owner)).send({ deviceId: d.id, title: 'Try again', price: 100, condition: 'good', city: 'Lahore' });
    assert.equal(relist.status, 409);
    const xfer = await api().post('/api/v1/transfers').set(auth(owner)).send({ deviceId: d.id, recipientEmail: buyer.email });
    assert.equal(xfer.status, 409);
    assert.equal((await api().post(`/api/v1/admin/reports/${rep.body.report.id}/reject`).set(auth(admin)).send({})).status, 409, 'cannot re-review');

    const flags = await api().get('/api/v1/admin/flags').set(auth(admin));
    assert.equal(flags.status, 200);
    assert.ok(flags.body.flags.some((f) => f.type === 'stolen_imei_lookups'));
  });
});

describe('uploads & integrity', () => {
  test('upload rejects a file whose content is not really an image', async () => {
    const u = await h.registerUser('Uploader');
    const l = await h.createListing(u, await h.registerDevice(u));
    const fake = await api().post(`/api/v1/listings/${l.id}/images`).set(auth(u))
      .attach('images', Buffer.from('<?php echo 1; ?>'), { filename: 'phone.jpg', contentType: 'image/jpeg' });
    assert.equal(fake.status, 400);
    const png = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010806000000', 'hex');
    const real = await api().post(`/api/v1/listings/${l.id}/images`).set(auth(u)).attach('images', png, { filename: 'p.png', contentType: 'image/png' });
    assert.equal(real.status, 201);
    // Signed media URL works; tampered signature does not.
    const url = new URL(real.body.images[0].url);
    assert.equal((await api().get(url.pathname + url.search)).status, 200);
    assert.equal((await api().get(`${url.pathname}?exp=${url.searchParams.get('exp')}&sig=bad`)).status, 403);
    const other = await h.registerUser('NotOwner');
    const sneak = await api().post(`/api/v1/listings/${l.id}/images`).set(auth(other)).attach('images', png, { filename: 'p.png', contentType: 'image/png' });
    assert.equal(sneak.status, 403);
  });

  test('audit log cannot be modified or deleted', async () => {
    await assert.rejects(h.pool.query('update audit_logs set action = $1', ['tampered']), /append-only/);
    await assert.rejects(h.pool.query('delete from audit_logs'), /append-only/);
  });
});

describe('password change', () => {
  test('revokes old sessions but keeps the current device signed in', async () => {
    const u = await h.registerUser('Pw');
    const res = await api().post('/api/v1/auth/change-password').set(auth(u)).send({ currentPassword: 'Passw0rd!', newPassword: 'N3wPassword' });
    assert.equal(res.status, 200);
    assert.equal((await api().post('/api/v1/auth/refresh').send({ refreshToken: u.refreshToken })).status, 401, 'old refresh token revoked');
    assert.equal((await api().post('/api/v1/auth/refresh').send({ refreshToken: res.body.refreshToken })).status, 200, 'new one works');
    assert.equal((await api().post('/api/v1/auth/login').send({ email: u.email, password: 'N3wPassword' })).status, 200);
  });
});
