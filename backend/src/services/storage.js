const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');
const multer = require('multer');
const env = require('../config/env');
const { badRequest } = require('../lib/errors');

const MAX_BYTES = 5 * 1024 * 1024;
const URL_TTL_SECONDS = 60 * 60;

// Detect the real type from the file's first bytes; the client's declared type is not trusted.
function sniffMime(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.length >= 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  if (buf.length >= 5 && buf.toString('ascii', 0, 5) === '%PDF-') return 'application/pdf';
  return null;
}
const EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'application/pdf': 'pdf' };

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: MAX_BYTES, files: 6 } });

/**
 * Validates an uploaded buffer and returns { mime, ext }.
 * @param {string[]} allowed - allowed mime types
 */
function checkFile(file, allowed) {
  if (!file) throw badRequest('No file uploaded');
  const mime = sniffMime(file.buffer);
  if (!mime || !allowed.includes(mime)) {
    throw badRequest(`Unsupported file type. Allowed: ${allowed.map((m) => EXT[m]).join(', ')}`);
  }
  return { mime, ext: EXT[mime] };
}

// ---------- Drivers ----------
let supabase = null;
function supabaseClient() {
  if (!supabase) {
    const { createClient } = require('@supabase/supabase-js');
    supabase = createClient(env.supabaseUrl, env.supabaseServiceRoleKey, { auth: { persistSession: false } });
  }
  return supabase;
}

const localRoot = path.resolve(env.localUploadDir);

function signLocal(p, exp) {
  return crypto.createHmac('sha256', env.jwtSecret).update(`${p}:${exp}`).digest('base64url');
}

/** Store a buffer under a server-generated key; returns the storage path. */
async function put(folder, buffer, mime) {
  const key = `${folder}/${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}.${EXT[mime]}`;
  if (env.storageDriver === 'supabase') {
    const { error } = await supabaseClient().storage.from(env.supabaseBucket).upload(key, buffer, { contentType: mime, upsert: false });
    if (error) throw new Error(`Storage upload failed: ${error.message}`);
  } else {
    const full = path.join(localRoot, key);
    await fs.mkdir(path.dirname(full), { recursive: true });
    await fs.writeFile(full, buffer);
  }
  return key;
}

async function remove(key) {
  if (env.storageDriver === 'supabase') {
    await supabaseClient().storage.from(env.supabaseBucket).remove([key]);
  } else {
    await fs.rm(path.join(localRoot, key), { force: true });
  }
}

/** Short-lived URL for a private object (bucket is private; nothing is publicly listable). */
async function signedUrl(key) {
  if (!key) return null;
  if (env.storageDriver === 'supabase') {
    const { data, error } = await supabaseClient().storage.from(env.supabaseBucket).createSignedUrl(key, URL_TTL_SECONDS);
    return error ? null : data.signedUrl;
  }
  const exp = Math.floor(Date.now() / 1000) + URL_TTL_SECONDS;
  return `${env.publicBaseUrl}/media/${key}?exp=${exp}&sig=${signLocal(key, exp)}`;
}

/** Express handler serving local files only with a valid, unexpired signature. */
function localMediaHandler(req, res) {
  const key = req.params.key.join('/');
  const exp = Number(req.query.exp);
  const sig = String(req.query.sig || '');
  const expected = signLocal(key, exp);
  const valid = Number.isFinite(exp) && exp > Date.now() / 1000
    && sig.length === expected.length && crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
  const full = path.resolve(localRoot, key);
  if (!valid || !full.startsWith(localRoot + path.sep)) return res.status(403).json({ error: { code: 'forbidden', message: 'Link expired' } });
  return res.sendFile(full, { headers: { 'Cache-Control': 'private, max-age=600', 'X-Content-Type-Options': 'nosniff' } }, (err) => {
    if (err && !res.headersSent) res.status(404).end();
  });
}

module.exports = { upload, checkFile, put, remove, signedUrl, localMediaHandler, sniffMime };
