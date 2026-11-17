import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { Pool } from 'pg';
import { hashPassword } from '../dist/password.js';

const publicDir = fileURLToPath(new URL('../../app/build/web/', import.meta.url));

async function startApi(t, databaseUrl, localDevelopment = true, extraEnv = {}) {
  const child = spawn(process.execPath, [fileURLToPath(new URL('../dist/server.js', import.meta.url))], {
    env: { ...process.env, DATABASE_URL: databaseUrl, PUBLIC_DIR: publicDir, HOST: '127.0.0.1', PORT: '0', INVENTORY_LOCAL_DEV: String(localDevelopment), NODE_ENV: 'test', APP_ORIGIN: '', ...extraEnv },
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const exit = once(child, 'close');
  t.after(async () => {
    child.kill();
    await exit;
  });

  const address = await Promise.race([
    (async () => {
      let output = '';
      for await (const chunk of child.stdout.iterator({ destroyOnReturn: false })) {
        output += chunk;
        const match = output.match(/Server listening at (http:\/\/127\.0\.0\.1:\d+)/);
        if (match) return match[1];
      }
      throw new Error(`La API terminó antes de escuchar. ${output}`);
    })(),
    delay(10000, null, { ref: false }),
  ]);
  assert.ok(address, 'La API debe iniciar en menos de 10 segundos');
  child.stdout.resume();
  return address;
}

test('La API consulta PostgreSQL y sirve el bundle web', async (t) => {
  assert.ok(process.env.TEST_DATABASE_URL, 'Se requiere una base de prueba migrada');
  const pool = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
  const name = `Sala de prueba ${randomUUID()}`;
  const code = randomUUID();
  t.after(async () => {
    try {
      await pool.query('DELETE FROM assets WHERE code = $1', [code]);
      await pool.query('DELETE FROM rooms WHERE name = $1', [name]);
    } finally {
      await pool.end();
    }
  });
  const room = await pool.query('INSERT INTO rooms (name) VALUES ($1) RETURNING id', [name]);
  await pool.query('INSERT INTO assets (code, name, type, room_id) VALUES ($1, $2, $3, $4)',
    [code, 'Equipo de prueba', 'Computador', room.rows[0].id]);

  const address = await startApi(t, process.env.TEST_DATABASE_URL);
  const health = await fetch(`${address}/api/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { status: 'ok', database: 'connected' });

  const rooms = await fetch(`${address}/api/rooms`);
  assert.equal(rooms.status, 200);
  assert.equal((await rooms.json()).find((room) => room.name === name)?.asset_count, 1);

  for (const path of ['/', '/salas/prueba']) {
    const page = await fetch(`${address}${path}`);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /flutter_bootstrap\.js/);
  }
  const script = await fetch(`${address}/main.dart.js`);
  assert.equal(script.status, 200);
  assert.match(script.headers.get('content-type'), /javascript/);
  await script.body.cancel();

  const missing = await fetch(`${address}/api/desconocido`);
  assert.equal(missing.status, 404);
  assert.match(missing.headers.get('content-type'), /application\/json/);
});

test('Alta, historial y plano sobreviven a otra instancia de la API', async (t) => {
  assert.ok(process.env.TEST_DATABASE_URL, 'Se requiere una base de prueba migrada');
  const owner = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
  const runtimeUrl = process.env.TEST_APPLICATION_DATABASE_URL ?? process.env.TEST_DATABASE_URL;
  const code = randomUUID();
  const name = `Sala persistencia ${randomUUID()}`;
  t.after(async () => {
    try {
      await owner.query('DELETE FROM asset_status_history WHERE asset_id IN (SELECT id FROM assets WHERE code = $1)', [code]);
      await owner.query('DELETE FROM assets WHERE code = $1', [code]);
      await owner.query('DELETE FROM rooms WHERE name = $1', [name]);
    } finally {
      await owner.end();
    }
  });
  const { rows: [{ id: roomId }] } = await owner.query('INSERT INTO rooms (name) VALUES ($1) RETURNING id', [name]);
  const origin = await startApi(t, runtimeUrl);
  const write = (path, method, body) => fetch(`${origin}/api${path}`, {
    method, headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });

  const input = { code, name: 'Equipo persistente', type: 'Computador', roomId };
  const created = await write('/assets', 'POST', input);
  assert.equal(created.status, 201);
  const asset = await created.json();
  assert.equal(asset.status, 'unknown');
  assert.equal((await write('/assets', 'POST', input)).status, 409);

  const statusPath = `/assets/${asset.id}/status`;
  const results = await Promise.all([
    write(statusPath, 'PATCH', { status: 'operational', version: 1, note: 'Comprobado por TI' }),
    write(statusPath, 'PATCH', { status: 'faulty', version: 1, note: 'Comprobado por TI' }),
  ]);
  assert.deepEqual(results.map((result) => result.status).sort(), [200, 409]);
  const accepted = await results.find((result) => result.status === 200).json();
  assert.equal((await write(statusPath, 'PATCH', { status: accepted.status, version: 2 })).status, 200);

  const layoutPath = `/rooms/${roomId}/layout`;
  const layout = {
    version: 1,
    positions: [{ assetId: asset.id, x: 0.25, y: 0.75 }],
    items: [{ kind: 'rack', label: 'Rack', x: 0, y: 0, width: 0.25, height: 0.25 }],
  };
  assert.equal((await write(layoutPath, 'PUT', layout)).status, 200);
  assert.equal((await write(layoutPath, 'PUT', layout)).status, 409);
  assert.equal((await write(layoutPath, 'PUT', {
    ...layout, version: 2, positions: [{ assetId: randomUUID(), x: 0.5, y: 0.5 }],
  })).status, 400);

  const independent = await startApi(t, runtimeUrl);
  const room = await (await fetch(`${independent}/api/rooms/${roomId}`)).json();
  assert.equal(room.layout_version, 2);
  assert.equal(room.assets[0].status, accepted.status);
  assert.deepEqual([room.assets[0].x, room.assets[0].y], [0.25, 0.75]);
  assert.equal(room.items[0].label, 'Rack');
  const history = await (await fetch(`${independent}/api/assets/${asset.id}/history`)).json();
  assert.equal(history.length, 1);
  assert.equal(history[0].previous_status, 'unknown');
  assert.equal(history[0].new_status, accepted.status);
  assert.equal(history[0].note, 'Comprobado por TI');

  const disabled = await startApi(t, runtimeUrl, false);
  assert.equal((await fetch(`${disabled}/api/rooms`)).status, 401);
});

test('Autenticación de TI protege datos, persiste sesiones y registra al operador', async (t) => {
  const pool = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
  const username = 'ti-' + randomUUID();
  const password = 'Cuenta de prueba 2026!';
  let roomId;
  const { rows: [user] } = await pool.query(
    'INSERT INTO auth_users (username, display_name, password_hash) VALUES ($1, $2, $3) RETURNING id',
    [username, 'Persona de TI', await hashPassword(password)],
  );
  t.after(async () => {
    try {
      if (roomId) {
        await pool.query('DELETE FROM asset_status_history WHERE asset_id IN (SELECT id FROM assets WHERE room_id = $1)', [roomId]);
        await pool.query('DELETE FROM assets WHERE room_id = $1', [roomId]);
        await pool.query('DELETE FROM rooms WHERE id = $1', [roomId]);
      }
      await pool.query('DELETE FROM auth_users WHERE id = $1', [user.id]);
    } finally { await pool.end(); }
  });
  const originHeader = 'https://inventario.test';
  const production = { NODE_ENV: 'production', APP_ORIGIN: originHeader };
  const address = await startApi(t, process.env.TEST_APPLICATION_DATABASE_URL ?? process.env.TEST_DATABASE_URL, false, production);
  const jsonHeaders = { 'content-type': 'application/json', 'x-inventory-request': '1', origin: originHeader };
  const login = (body, headers = jsonHeaders) => fetch(address + '/api/auth/login', {
    method: 'POST', headers, body: JSON.stringify(body),
  });
  const input = { username, password };
  assert.equal((await fetch(address + '/api/rooms')).status, 401);
  assert.equal((await login({ ...input, password: 'incorrecta' })).status, 401);
  assert.equal((await login(input, { ...jsonHeaders, origin: 'https://otro.test' })).status, 403);
  assert.equal((await login(input, { 'content-type': 'application/json' })).status, 403);
  const logged = await login(input);
  assert.equal(logged.status, 200);
  const cookieHeader = logged.headers.get('set-cookie');
  assert.match(cookieHeader, /HttpOnly/i);
  assert.match(cookieHeader, /Secure/i);
  assert.match(cookieHeader, /SameSite=Lax/i);
  assert.equal((await logged.json()).token, undefined);
  const cookie = cookieHeader.split(';')[0];
  const signed = { ...jsonHeaders, cookie };
  const second = await startApi(t, process.env.TEST_APPLICATION_DATABASE_URL ?? process.env.TEST_DATABASE_URL, false, production);
  const me = await fetch(second + '/api/auth/me', { headers: { cookie } });
  assert.equal(me.status, 200);
  assert.equal((await me.json()).user.username, username);

  const roomResponse = await fetch(address + '/api/rooms', { method: 'POST', headers: signed, body: JSON.stringify({ name: username }) });
  assert.equal(roomResponse.status, 201);
  roomId = (await roomResponse.json()).id;
  const created = await fetch(address + '/api/assets', {
    method: 'POST', headers: signed,
    body: JSON.stringify({ code: username, name: 'Equipo autenticado', type: 'Computador', roomId }),
  });
  assert.equal(created.status, 201);
  const asset = await created.json();
  const changed = await fetch(address + '/api/assets/' + asset.id + '/status', {
    method: 'PATCH', headers: signed, body: JSON.stringify({ status: 'operational', version: 1 }),
  });
  assert.equal(changed.status, 200);
  const history = await (await fetch(address + '/api/assets/' + asset.id + '/history', { headers: { cookie } })).json();
  assert.equal(history[0].operator_id, username);

  const desktopResponse = await login({ ...input, desktop: true });
  const desktop = await desktopResponse.json();
  const bearer = { authorization: 'Bearer ' + desktop.token, 'x-inventory-request': '1' };
  assert.equal((await fetch(second + '/api/rooms', { headers: bearer })).status, 200);
  const stored = await pool.query('SELECT token_hash FROM auth_sessions WHERE user_id = $1', [user.id]);
  assert.ok(stored.rows.every((session) => session.token_hash !== desktop.token));
  assert.equal((await fetch(address + '/api/auth/logout', { method: 'POST', headers: { cookie, 'x-inventory-request': '1', origin: originHeader } })).status, 200);
  assert.equal((await fetch(second + '/api/rooms', { headers: { cookie } })).status, 401);

  await pool.query("UPDATE auth_sessions SET expires_at = now() - interval '1 second' WHERE user_id = $1", [user.id]);
  assert.equal((await fetch(second + '/api/rooms', { headers: bearer })).status, 401);
  const fresh = await (await login({ ...input, desktop: true })).json();
  await pool.query('UPDATE auth_users SET active = false WHERE id = $1', [user.id]);
  assert.equal((await fetch(second + '/api/rooms', { headers: { authorization: 'Bearer ' + fresh.token } })).status, 401);
  assert.equal((await login(input)).status, 401);

  let limited = false;
  for (let i = 0; i < 22; i++) {
    const attempt = await login({ username: 'inexistente', password: 'incorrecta' });
    if (attempt.status === 429) { limited = true; break; }
  }
  assert.equal(limited, true, 'El login debe limitar intentos repetidos');
});

test('Una cuenta creada en pgAdmin permite ingresar y revoca sesiones al cambiar la clave', async (t) => {
  const pool = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
  const username = 'sql-' + randomUUID();
  const password = 'p'.repeat(72);
  const template = readFileSync(new URL('../sql/cuenta-ti.sql', import.meta.url), 'utf8');
  const accountSql = (secret) => template
    .replace("'tecnico'", () => "'" + username + "'")
    .replace("'CAMBIAR_POR_UNA_CLAVE_PERSONAL'", () => "'" + secret + "'");
  t.after(async () => {
    await pool.query('DELETE FROM auth_users WHERE username = $1', [username]);
    await pool.end();
  });
  await pool.query(accountSql(password));
  const address = await startApi(t, process.env.TEST_APPLICATION_DATABASE_URL ?? process.env.TEST_DATABASE_URL, false);
  const login = (secret) => fetch(address + '/api/auth/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-inventory-request': '1' },
    body: JSON.stringify({ username, password: secret, desktop: true }),
  });
  assert.equal((await login('incorrecta')).status, 401);
  assert.equal((await login(password + 'otro')).status, 401);
  const first = await login(password);
  assert.equal(first.status, 200);
  const token = (await first.json()).token;
  await pool.query(accountSql('Nueva clave de prueba 2026!'));
  assert.equal((await fetch(address + '/api/rooms', { headers: { authorization: 'Bearer ' + token } })).status, 401);
  assert.equal((await login(password)).status, 401);
  assert.equal((await login('Nueva clave de prueba 2026!')).status, 200);
});
