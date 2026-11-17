export async function up(pgm) {
  pgm.createTable('auth_users', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') },
    username: { type: 'text', notNull: true, unique: true },
    display_name: { type: 'text', notNull: true },
    password_hash: { type: 'text', notNull: true },
    active: { type: 'boolean', notNull: true, default: true },
  });
  pgm.createTable('auth_sessions', {
    token_hash: { type: 'text', primaryKey: true },
    user_id: { type: 'uuid', notNull: true, references: 'auth_users', onDelete: 'cascade' },
    expires_at: { type: 'timestamptz', notNull: true },
  });
  pgm.createIndex('auth_sessions', 'expires_at');
}

export async function down(pgm) {
  pgm.dropTable('auth_sessions');
  pgm.dropTable('auth_users');
}
