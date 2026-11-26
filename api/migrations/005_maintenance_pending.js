export async function up(pgm) {
  pgm.addColumn('assets', {
    maintenance_pending: { type: 'boolean', notNull: true, default: false },
  });
}

export async function down(pgm) {
  pgm.dropColumn('assets', 'maintenance_pending');
}
