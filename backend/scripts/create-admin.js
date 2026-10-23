/**
 * Creates (or promotes) an admin account. Admin role can only be granted here,
 * from a machine that has DATABASE_URL — never through the public API.
 *
 * Usage: npm run seed:admin -- admin@example.com "Admin Name" "StrongPassw0rd"
 */
const bcrypt = require('bcryptjs');
const { pool } = require('../src/lib/db');

async function main() {
  const [email, fullName, password] = process.argv.slice(2);
  if (!email || !fullName || !password) {
    console.error('Usage: npm run seed:admin -- <email> "<full name>" "<password>"');
    process.exit(1);
  }
  if (password.length < 10) {
    console.error('Use an admin password of at least 10 characters.');
    process.exit(1);
  }
  const hash = await bcrypt.hash(password, 12);
  const { rows } = await pool.query(
    `insert into users (email, full_name, password_hash, role) values (lower($1), $2, $3, 'admin')
     on conflict (email) do update set role = 'admin', password_hash = excluded.password_hash, status = 'active'
     returning id, email`,
    [email, fullName, hash],
  );
  await pool.query(`insert into audit_logs (actor_id, action, entity_type, entity_id) values ($1::uuid, 'admin.created_via_script', 'user', $1::text)`, [rows[0].id]);
  console.log(`Admin ready: ${rows[0].email}`);
}

main().then(() => pool.end()).catch((err) => { console.error(err.message); pool.end(); process.exit(1); });
