export const shorthands = undefined;

export async function up(pgm) {
  pgm.addColumn('assets', {
    icon: {
      type: 'text',
      notNull: true,
      default: 'generic',
      check:
        "icon IN ('generic','computer','laptop','server','switch','router','accessPoint','phone','printer','ups','patchPanel','camera','screen')",
    },
  });
}

export async function down(pgm) {
  pgm.dropColumn('assets', 'icon');
}
