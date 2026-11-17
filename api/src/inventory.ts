import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import type { Pool, PoolClient } from 'pg';

const id = { type: 'string', format: 'uuid' } as const;
const idParams = {
  type: 'object', required: ['id'], properties: { id }, additionalProperties: false,
} as const;
const version = { type: 'integer', minimum: 1 } as const;
const coordinate = { type: 'number', minimum: 0, maximum: 1 } as const;
const statusValues = ['unknown', 'operational', 'faulty', 'maintenance', 'offline'] as const;
const iconValues = [
  'generic', 'computer', 'laptop', 'server', 'switch', 'router', 'accessPoint',
  'phone', 'printer', 'ups', 'patchPanel', 'camera', 'screen',
] as const;
type Status = typeof statusValues[number];
type Icon = typeof iconValues[number];
type Id = { Params: { id: string } };
type StatusChange = { status: Status; version: number; note?: string };
type AssetInput = { code: string; name: string; type: string; roomId?: string; icon?: Icon };
type RoomInput = { name: string };
type Position = { assetId: string; x: number; y: number };
type LayoutItem = {
  kind: 'table' | 'row' | 'rack';
  label?: string;
  x: number;
  y: number;
  width: number;
  height: number;
};
type Layout = { version: number; positions: Position[]; items: LayoutItem[] };

async function transact<T>(pool: Pool, work: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export function registerInventoryRoutes(
  app: FastifyInstance,
  pool: Pool,
  requireUser: (request: FastifyRequest, reply: FastifyReply) => Promise<unknown>,
) {
  app.addHook('onRequest', requireUser);

  app.post<{ Body: RoomInput }>('/rooms', {
    schema: { body: {
      type: 'object', required: ['name'], additionalProperties: false,
      properties: { name: { type: 'string', minLength: 1, maxLength: 120 } },
    } },
  }, async (request, reply) => {
    const name = request.body.name.trim();
    if (!name) return reply.code(400).send({ error: 'Escribe un nombre para la sala' });
    try {
      const result = await pool.query('INSERT INTO rooms (name) VALUES ($1) RETURNING *', [name]);
      return reply.code(201).send(result.rows[0]);
    } catch (error) {
      if ((error as { code?: string }).code === '23505') {
        return reply.code(409).send({ error: 'Ya existe una sala con ese nombre' });
      }
      throw error;
    }
  });

  app.get('/rooms', async () => {
    const result = await pool.query(`
      SELECT r.id, r.name, r.layout_version, count(a.id)::int AS asset_count,
             count(a.id) FILTER (WHERE a.status = 'unknown')::int AS unknown_count,
             count(a.id) FILTER (WHERE a.status = 'operational')::int AS operational_count,
             count(a.id) FILTER (WHERE a.status = 'faulty')::int AS faulty_count,
             count(a.id) FILTER (WHERE a.status = 'maintenance')::int AS maintenance_count,
             count(a.id) FILTER (WHERE a.status = 'offline')::int AS offline_count
      FROM rooms r LEFT JOIN assets a ON a.room_id = r.id
      GROUP BY r.id ORDER BY r.name`);
    return result.rows;
  });

  app.get<Id>('/rooms/:id', { schema: { params: idParams } }, async (request, reply) => {
    const result = await pool.query(`
      SELECT r.*,
        COALESCE((
          SELECT jsonb_agg(to_jsonb(a) || jsonb_build_object('x', p.x, 'y', p.y) ORDER BY a.code)
          FROM assets a LEFT JOIN asset_positions p ON p.asset_id = a.id AND p.room_id = r.id
          WHERE a.room_id = r.id
        ), '[]'::jsonb) AS assets,
        COALESCE((
          SELECT jsonb_agg(to_jsonb(i) ORDER BY i.id) FROM room_items i WHERE i.room_id = r.id
        ), '[]'::jsonb) AS items
      FROM rooms r WHERE r.id = $1`, [request.params.id]);
    return result.rows[0] ?? reply.code(404).send({ error: 'Sala no encontrada' });
  });

  app.post<{ Body: AssetInput }>('/assets', {
    schema: { body: {
      type: 'object', required: ['code', 'name', 'type'], additionalProperties: false,
      properties: {
        code: { type: 'string', minLength: 1, maxLength: 64 },
        name: { type: 'string', minLength: 1, maxLength: 200 },
        type: { type: 'string', minLength: 1, maxLength: 80 },
        roomId: id,
        icon: { type: 'string', enum: iconValues },
      },
    } },
  }, async (request, reply) => {
    const { roomId, icon } = request.body;
    const { code, name, type } = request.body;
    const values = [code.trim(), name.trim(), type.trim()];
    if (values.some((value) => !value)) {
      return reply.code(400).send({ error: 'Completa el código, el nombre y el tipo del equipo' });
    }
    try {
      const result = await pool.query(`
        INSERT INTO assets (code, name, type, room_id, icon) VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [...values, roomId ?? null, icon ?? 'generic']);
      return reply.code(201).send(result.rows[0]);
    } catch (error) {
      const pgError = error as { code?: string };
      if (pgError.code === '23505') return reply.code(409).send({ error: 'El código del equipo ya existe' });
      if (pgError.code === '23503') return reply.code(404).send({ error: 'Sala no encontrada' });
      throw error;
    }
  });

  app.get<Id>('/assets/:id', { schema: { params: idParams } }, async (request, reply) => {
    const result = await pool.query('SELECT * FROM assets WHERE id = $1', [request.params.id]);
    return result.rows[0] ?? reply.code(404).send({ error: 'Equipo no encontrado' });
  });

  app.get<Id>('/assets/:id/history', { schema: { params: idParams } }, async (request, reply) => {
    const result = await pool.query(`
      SELECT COALESCE((
        SELECT jsonb_agg(h ORDER BY h.changed_at DESC, h.id DESC)
        FROM asset_status_history h WHERE h.asset_id = a.id
      ), '[]'::jsonb) AS history
      FROM assets a WHERE a.id = $1`, [request.params.id]);
    return result.rows[0]?.history ?? reply.code(404).send({ error: 'Equipo no encontrado' });
  });

  app.patch<Id & { Body: StatusChange }>('/assets/:id/status', {
    schema: {
      params: idParams,
      body: {
        type: 'object', required: ['status', 'version'], additionalProperties: false,
        properties: {
          status: { type: 'string', enum: statusValues }, version,
          note: { type: 'string', maxLength: 2000 },
        },
      },
    },
  }, async (request, reply) => {
    const { id: assetId } = request.params;
    const { status, version: expected, note } = request.body;
    const outcome = await transact(pool, async (client) => {
      const lock = await client.query('SELECT * FROM assets WHERE id = $1 FOR UPDATE', [assetId]);
      const asset = lock.rows[0];
      if (!asset) return { code: 404, body: { error: 'Equipo no encontrado' } };
      if (asset.status_version !== expected) {
        return { code: 409, body: { error: 'El estado cambió', current: asset } };
      }
      if (asset.status === status) return { code: 200, body: asset };

      const updated = await client.query(`
        UPDATE assets
        SET status = $2, status_version = status_version + 1, status_updated_at = now()
        WHERE id = $1 RETURNING *`, [assetId, status]);
      await client.query(`
        INSERT INTO asset_status_history (asset_id, previous_status, new_status, note, operator_id)
        VALUES ($1, $2, $3, $4, $5)`, [assetId, asset.status, status, note?.trim() ?? '', request.user!.username]);
      return { code: 200, body: updated.rows[0] };
    });
    return reply.code(outcome.code).send(outcome.body);
  });

  app.patch<Id & { Body: { icon: Icon } }>('/assets/:id/icon', {
    schema: {
      params: idParams,
      body: {
        type: 'object', required: ['icon'], additionalProperties: false,
        properties: { icon: { type: 'string', enum: iconValues } },
      },
    },
  }, async (request, reply) => {
    const result = await pool.query(
      'UPDATE assets SET icon = $2 WHERE id = $1 RETURNING *',
      [request.params.id, request.body.icon]);
    return result.rows[0] ?? reply.code(404).send({ error: 'Equipo no encontrado' });
  });

  app.put<Id & { Body: Layout }>('/rooms/:id/layout', {
    schema: {
      params: idParams,
      body: {
        type: 'object', required: ['version', 'positions', 'items'], additionalProperties: false,
        properties: {
          version,
          positions: {
            type: 'array', maxItems: 1000,
            items: {
              type: 'object', required: ['assetId', 'x', 'y'], additionalProperties: false,
              properties: { assetId: id, x: coordinate, y: coordinate },
            },
          },
          items: {
            type: 'array', maxItems: 1000,
            items: {
              type: 'object', required: ['kind', 'x', 'y', 'width', 'height'], additionalProperties: false,
              properties: {
                kind: { type: 'string', enum: ['table', 'row', 'rack'] },
                label: { type: 'string', maxLength: 120 },
                x: coordinate, y: coordinate,
                width: { ...coordinate, exclusiveMinimum: 0 },
                height: { ...coordinate, exclusiveMinimum: 0 },
              },
            },
          },
        },
      },
    },
  }, async (request, reply) => {
    const roomId = request.params.id;
    const { positions, items, version: expected } = request.body;
    const assetIds = positions.map((position) => position.assetId.toLowerCase());
    if (new Set(assetIds).size !== assetIds.length) {
      return reply.code(400).send({ error: 'Un equipo aparece más de una vez en el plano' });
    }
    if (items.some(({ x, y, width, height }) => x + width > 1 || y + height > 1)) {
      return reply.code(400).send({ error: 'Una figura queda fuera del plano' });
    }

    const outcome = await transact(pool, async (client) => {
      const lock = await client.query('SELECT layout_version FROM rooms WHERE id = $1 FOR UPDATE', [roomId]);
      const current = lock.rows[0]?.layout_version;
      if (current === undefined) return { code: 404, body: { error: 'Sala no encontrada' } };
      if (current !== expected) {
        return { code: 409, body: { error: 'La distribución cambió', layout_version: current } };
      }

      const members = await client.query('SELECT id FROM assets WHERE room_id = $1 AND id = ANY($2::uuid[])', [roomId, assetIds]);
      if (members.rowCount !== assetIds.length) {
        return { code: 400, body: { error: 'Uno o más equipos no pertenecen a la sala' } };
      }

      await client.query('DELETE FROM asset_positions WHERE room_id = $1', [roomId]);
      await client.query(`
        INSERT INTO asset_positions (asset_id, room_id, x, y)
        SELECT "assetId", $1, x, y FROM jsonb_to_recordset($2::jsonb) AS p("assetId" uuid, x real, y real)
      `, [roomId, JSON.stringify(positions)]);
      await client.query('DELETE FROM room_items WHERE room_id = $1', [roomId]);
      await client.query(`
        INSERT INTO room_items (room_id, kind, label, x, y, width, height)
        SELECT $1, kind, COALESCE(label, ''), x, y, width, height
        FROM jsonb_to_recordset($2::jsonb) AS i(kind text, label text, x real, y real, width real, height real)
      `, [roomId, JSON.stringify(items)]);

      const updated = await client.query(`
        UPDATE rooms SET layout_version = layout_version + 1 WHERE id = $1 RETURNING layout_version`, [roomId]);
      return { code: 200, body: updated.rows[0] };
    });
    return reply.code(outcome.code).send(outcome.body);
  });
}
