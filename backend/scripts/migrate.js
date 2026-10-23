/**
 * Applies SQL files from ../supabase/migrations in filename order, once each.
 * Usage: npm run migrate            (uses DATABASE_URL)
 *        NODE_ENV=test npm run migrate (uses TEST_DATABASE_URL)
 *
 * You can also apply the same files with the Supabase CLI (`supabase db push`)
 * or by pasting them into the Supabase SQL editor — use one method consistently.
 */
const fs = require('fs');
const path = require('path');
const { pool } = require('../src/lib/db');

const dir = path.resolve(__dirname, '../../supabase/migrations');

async function migrate({ log = console.log } = {}) {
  const client = await pool.connect();
  try {
    await client.query(`create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())`);
    await client.query('alter table schema_migrations enable row level security');
    const done = new Set((await client.query('select name from schema_migrations')).rows.map((r) => r.name));
    const files = fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
    for (const file of files) {
      if (done.has(file)) continue;
      const sql = fs.readFileSync(path.join(dir, file), 'utf8');
      log(`Applying ${file} ...`);
      await client.query('begin');
      try {
        await client.query(sql);
        await client.query('insert into schema_migrations (name) values ($1)', [file]);
        await client.query('commit');
      } catch (err) {
        await client.query('rollback');
        throw new Error(`${file} failed: ${err.message}`);
      }
    }
    log('Migrations up to date.');
  } finally {
    client.release();
  }
}

if (require.main === module) {
  migrate().then(() => pool.end()).catch((err) => { console.error(err.message); pool.end(); process.exit(1); });
}

module.exports = { migrate };
