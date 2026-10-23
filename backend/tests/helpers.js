process.env.NODE_ENV = 'test';
process.env.STORAGE_DRIVER = 'local';
process.env.LOCAL_UPLOAD_DIR = process.env.LOCAL_UPLOAD_DIR_TEST || require('path').join(require('os').tmpdir(), 'devicetrust-test-uploads');

const request = require('supertest');
const app = require('../src/app');
const { pool } = require('../src/lib/db');
const { migrate } = require('../scripts/migrate');
const { luhnCheckDigit } = require('../src/lib/imei');

const TABLES = ['audit_logs', 'imei_lookups', 'notifications', 'disputes', 'documents', 'stolen_reports',
  'ownership_history', 'ownership_transfers', 'purchase_requests', 'listing_images', 'listings',
  'device_imeis', 'devices', 'refresh_tokens', 'users'];

async function resetDb() {
  await migrate({ log: () => {} });
  // audit_logs blocks DELETE via trigger; TRUNCATE is allowed for test resets.
  await pool.query(`truncate ${TABLES.join(', ')} restart identity cascade`);
}

let seq = 0;
/** Generates a fresh IMEI with a valid Luhn check digit. */
function makeImei() {
  seq += 1;
  const body = `35${String(Date.now() % 1e6).padStart(6, '0')}${String(seq).padStart(6, '0')}`.slice(0, 14);
  return body + luhnCheckDigit(body);
}

const api = () => request(app);

async function registerUser(name = 'User') {
  seq += 1;
  const email = `${name.toLowerCase().replace(/\W/g, '')}${seq}@example.com`;
  const res = await api().post('/api/v1/auth/register').send({ email, password: 'Passw0rd!', fullName: `${name} Tester` });
  if (res.status !== 201) throw new Error(`register failed: ${JSON.stringify(res.body)}`);
  return { ...res.body.user, token: res.body.accessToken, refreshToken: res.body.refreshToken };
}

async function makeAdmin(user) {
  await pool.query(`update users set role = 'admin' where id = $1`, [user.id]);
  return user;
}

const auth = (u) => ({ Authorization: `Bearer ${u.token}` });

async function registerDevice(user, extra = {}) {
  const res = await api().post('/api/v1/devices').set(auth(user))
    .send({ imei1: makeImei(), brand: 'Samsung', model: 'Galaxy S23', storageGb: 256, ...extra });
  if (res.status !== 201) throw new Error(`device failed: ${JSON.stringify(res.body)}`);
  return res.body.device;
}

async function createListing(user, device, extra = {}) {
  const res = await api().post('/api/v1/listings').set(auth(user))
    .send({ deviceId: device.id, title: 'Galaxy S23 256GB', price: 150000, condition: 'good', city: 'Rawalpindi', ...extra });
  if (res.status !== 201) throw new Error(`listing failed: ${JSON.stringify(res.body)}`);
  return res.body.listing;
}

module.exports = { api, pool, resetDb, makeImei, registerUser, makeAdmin, auth, registerDevice, createListing };
