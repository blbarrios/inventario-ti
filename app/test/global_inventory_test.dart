import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_ti/main.dart';
import 'package:inventario_ti/all_assets_page.dart';

void main() {
  testWidgets('El marcador muestra nombre y persona asignada', (tester) async {
    final asset = Asset(
        'PC-99', 'Equipo contabilidad', 'Computador', const Offset(.2, .2),
        responsible: 'Ana Pérez');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: SizedBox(
          width: 320,
          height: 104,
          child: Marker(
            asset: asset,
            selected: false,
            onTap: () {},
            compact: false,
          )),
    ))));
    expect(find.text('Equipo contabilidad'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('PC-99'), findsNothing);
  });

  testWidgets('El tablero global filtra por mantenimiento y conserva la marca',
      (tester) async {
    final repo = DemoInventoryRepository();
    final rooms = await repo.loadRooms();
    final asset = rooms.first.assets.first;
    asset.responsible = 'Ana Pérez';
    await repo.updateMaintenance(asset, true);
    await tester.pumpWidget(
        MaterialApp(home: AllAssetsPage(repo: repo, editable: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(find.text('1 de 7 equipos'), findsOneWidget);
    expect(find.textContaining('Ana Pérez'), findsOneWidget);
    expect(find.text('Router Starlink'), findsNothing);
    await tester.enterText(find.byType(TextField), 'ana');
    await tester.pumpAndSettle();
    await tester.tap(find.text(asset.name));
    await tester.pumpAndSettle();
    final toggle = find.byType(SwitchListTile);
    await tester.scrollUntilVisible(toggle, 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(asset.maintenancePending, false);
    expect(asset.status, AssetStatus.unknown);
  });

  testWidgets('El inicio lista los equipos con mantenimiento pendiente',
      (tester) async {
    final repo = DemoInventoryRepository();
    final rooms = await repo.loadRooms();
    final asset = rooms.first.assets.first;
    await tester.pumpWidget(InventoryApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.text('Mantenimiento pendiente'), findsNothing);

    await repo.updateMaintenance(asset, true);
    await tester.pumpWidget(InventoryApp(repository: repo, key: UniqueKey()));
    await tester.pumpAndSettle();
    expect(find.text('Mantenimiento pendiente'), findsOneWidget);
    expect(find.text(asset.name), findsOneWidget);

    await tester.tap(find.text(asset.name));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsOneWidget);
  });
}
