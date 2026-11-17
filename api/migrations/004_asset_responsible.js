export const shorthands = undefined;

export async function up(pgm) {
  pgm.addColumn('assets', {
    responsible: { type: 'text', notNull: true, default: '' },
  });
}

export async function down(pgm) {
  pgm.dropColumn('assets', 'responsible');
}
