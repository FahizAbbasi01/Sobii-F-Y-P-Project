const { Pool } = require('pg');
const env = require('../config/env');

const pool = new Pool({
  connectionString: env.databaseUrl,
  ssl: env.databaseSsl ? { rejectUnauthorized: false } : undefined,
  max: 10,
});

// Return NUMERIC as JS numbers (prices fit comfortably in a double).
require('pg').types.setTypeParser(1700, (v) => (v === null ? null : Number(v)));

function query(text, params) {
  return pool.query(text, params);
}

/**
 * Run fn(client) inside a transaction. Rolls back on any thrown error.
 */
async function tx(fn) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const result = await fn(client);
    await client.query('commit');
    return result;
  } catch (err) {
    await client.query('rollback').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { pool, query, tx };
