import { Pool } from 'pg';
import { hashPassword } from './password.js';

// Run with the migration/owner connection. Never pass passwords as CLI arguments.
const username = process.env.TI_USERNAME?.trim().toLowerCase();
const displayName = process.env.TI_DISPLAY_NAME?.trim() || username;
const password = process.env.TI_PASSWORD;
const disable = process.argv.includes('--disable');
if (!username || !/^[a-z0-9._@-]{3,120}$/.test(username)) {
  throw new Error('Configura TI_USERNAME con 3 a 120 caracteres: letras, números, punto, guion, @ o _');
}
if (!disable && (!password || password.length < 12 || password.length > 256)) {
  throw new Error('Configura TI_PASSWORD con 12 a 256 caracteres');
}
const pool = new Pool({ connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 5000 });
const client = await pool.connect();
try {
  await client.query('BEGIN');
  await client.query('SELECT pg_advisory_xact_lock(7911, hashtext($1))', [username]);
  if (disable) {
    const result = await client.query('UPDATE auth_users SET active = false WHERE username = $1 RETURNING id', [username]);
    if (!result.rowCount) throw new Error('El usuario no existe');
  } else {
    await client.query(`
      INSERT INTO auth_users (username, display_name, password_hash) VALUES ($1, $2, $3)
      ON CONFLICT (username) DO UPDATE SET
        display_name = EXCLUDED.display_name, password_hash = EXCLUDED.password_hash, active = true
    `, [username, displayName, await hashPassword(password!)]);
  }
  await client.query('DELETE FROM auth_sessions WHERE user_id IN (SELECT id FROM auth_users WHERE username = $1)', [username]);
  await client.query('COMMIT');
  console.log(disable ? 'Cuenta deshabilitada y sesiones revocadas.' : 'Cuenta guardada y sesiones anteriores revocadas.');
} catch (error) {
  await client.query('ROLLBACK');
  throw error;
} finally {
  client.release();
  await pool.end();
}
