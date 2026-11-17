export const shorthands = undefined;

export async function up(pgm) {
  pgm.createExtension('pgcrypto', { ifNotExists: true });
  pgm.createTable('rooms', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') },
    name: { type: 'text', notNull: true, unique: true },
    canvas_width: { type: 'integer', notNull: true, default: 1200 },
    canvas_height: { type: 'integer', notNull: true, default: 800 },
    layout_version: { type: 'integer', notNull: true, default: 1 },
  });
  pgm.createTable('assets', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') },
    code: { type: 'text', notNull: true, unique: true }, name: { type: 'text', notNull: true }, type: { type: 'text', notNull: true },
    room_id: { type: 'uuid', references: 'rooms', onDelete: 'SET NULL' },
    status: { type: 'text', notNull: true, default: 'unknown', check: "status IN ('unknown','operational','faulty','maintenance','offline')" },
    status_version: { type: 'integer', notNull: true, default: 1 }, status_updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });
  pgm.createTable('room_items', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') }, room_id: { type: 'uuid', notNull: true, references: 'rooms', onDelete: 'cascade' },
    kind: { type: 'text', notNull: true, check: "kind IN ('table','row','rack')" }, label: { type: 'text', notNull: true, default: '' }, x: { type: 'real', notNull: true }, y: { type: 'real', notNull: true }, width: { type: 'real', notNull: true }, height: { type: 'real', notNull: true },
  });
  pgm.createTable('asset_positions', { asset_id: { type: 'uuid', primaryKey: true, references: 'assets', onDelete: 'cascade' }, room_id: { type: 'uuid', notNull: true, references: 'rooms', onDelete: 'cascade' }, x: { type: 'real', notNull: true, check: 'x BETWEEN 0 AND 1' }, y: { type: 'real', notNull: true, check: 'y BETWEEN 0 AND 1' } });
  pgm.createTable('asset_status_history', { id: 'id', asset_id: { type: 'uuid', notNull: true, references: 'assets' }, previous_status: { type: 'text', notNull: true }, new_status: { type: 'text', notNull: true }, note: { type: 'text', notNull: true, default: '' }, operator_id: { type: 'text', notNull: true }, changed_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') } });
}

export async function down(pgm) {
  pgm.dropTable('asset_status_history'); pgm.dropTable('asset_positions'); pgm.dropTable('room_items'); pgm.dropTable('assets'); pgm.dropTable('rooms');
}
