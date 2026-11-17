import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { Pool } from 'pg';

const publicDir = fileURLToPath(new URL('../../app/build/web/', import.meta.url));

async function startApi(t, databaseUrl, localDevelopment = true) {
  const child = spawn(process.execPath, [fileURLToPath(new URL('../dist/server.js', import.meta.url))], {
    env: { ...process.env, DATABASE_URL: databaseUrl, PUBLIC_DIR: publicDir, HOST: '127.0.0.1', PORT: '0', INVENTORY_LOCAL_DEV: String(localDevelopment) },
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
  assert.equal((await fetch(`${disabled}/api/rooms`)).status, 503);
});
