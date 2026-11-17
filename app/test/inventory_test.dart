import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_ti/main.dart';

/// All widget tests run against the in-memory demo repository.
Widget _app() => InventoryApp(repository: DemoInventoryRepository());

Widget _room(Room room, {bool editing = true, VoidCallback? onChanged}) =>
    MaterialApp(
      home: RoomPage(
        room: room,
        repo: DemoInventoryRepository(),
        editing: editing,
        onChanged: onChanged ?? () {},
      ),
    );

void main() {
  testWidgets('Las tres salas caben en una pantalla móvil', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Sala de sistemas 1'), findsOneWidget);
    expect(find.text('Sala de sistemas 2'), findsOneWidget);
    expect(find.text('Sala de bienestar'), findsOneWidget);
  });

  testWidgets('Cambiar estado y cerrar ficha conserva la sala', (tester) async {
    final asset =
        Asset('PC-01', 'Equipo piloto', 'Computador', const Offset(.2, .2));
    var changes = 0;
    await tester.pumpWidget(
        _room(Room('Sala piloto', [asset]), onChanged: () => changes++));

    await tester.tap(find.byType(Marker));
    await tester.pumpAndSettle();
    final operational = find.byKey(const ValueKey('status-operational'));
    await tester.scrollUntilVisible(operational, 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(operational);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar estado'));
    await tester.pumpAndSettle();

    expect(asset.status, AssetStatus.operational);
    expect(changes, 1);
    await tester.tap(find.byTooltip('Cerrar ficha'));
    await tester.pumpAndSettle();
    expect(find.text('Sala piloto'), findsOneWidget);
    expect(find.text('Equipos en la sala'), findsOneWidget);
  });

  testWidgets('La consulta protege el plano y el editor mueve marcadores',
      (tester) async {
    const start = Offset(.2, .2);
    final asset = Asset('PC-01', 'Equipo piloto', 'Computador', start);
    await tester.pumpWidget(_room(Room('Sala piloto', [asset])));

    await tester.drag(find.byType(Marker), const Offset(60, 30));
    await tester.pumpAndSettle();
    expect(asset.position, start);
    await tester.tap(find.text('Editar distribución'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Marker), const Offset(60, 30));
    await tester.pumpAndSettle();
    expect(asset.position, start);
    await tester.tap(find.text('Guardar plano'));
    await tester.pumpAndSettle();
    expect(asset.position.dx, greaterThan(start.dx));
  });

  testWidgets('En móvil se busca un equipo y se abre su ficha', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sala de sistemas 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equipos'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Starlink');
    await tester.pumpAndSettle();
    expect(find.text('Switch principal Cisco'), findsNothing);
    await tester.tap(find.text('Router Starlink'));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar estado'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar ficha'));
    await tester.pumpAndSettle();
    expect(find.text('Router Starlink'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Descartar revierte la edición y las flechas mueven sin arrastrar',
      (tester) async {
    const start = Offset(.3, .3);
    final asset = Asset('PC-01', 'Equipo piloto', 'Computador', start);
    await tester.pumpWidget(_room(Room('Sala piloto', [asset])));

    await tester.tap(find.text('Editar distribución'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Marker));
    await tester.pumpAndSettle();
    final before = tester.getCenter(find.byType(Marker));
    await tester.tap(find.byTooltip('Mover a la derecha'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byType(Marker)).dx, greaterThan(before.dx));
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byType(Marker)).dx, before.dx);
    expect(asset.position, start);
  });

  testWidgets('Presentación permite consultar sin controles de edición',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Presentación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sala de sistemas 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Marker).first);
    await tester.pumpAndSettle();
    expect(find.text('Switch principal Cisco'), findsOneWidget);
    expect(find.text('Editar distribución'), findsNothing);
    expect(find.text('Guardar estado'), findsNothing);
  });

  testWidgets('Se agrega una sala desde el inicio', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar sala'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bodega de red');
    await tester.tap(find.widgetWithText(FilledButton, 'Agregar sala'));
    await tester.pumpAndSettle();

    // Opens the new room, then back to the list which now includes it.
    expect(find.text('Agregar el primer equipo'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Bodega de red'), findsOneWidget);
  });

  testWidgets('No se permiten salas con nombre repetido', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar sala'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sala de bienestar');
    await tester.tap(find.widgetWithText(FilledButton, 'Agregar sala'));
    await tester.pumpAndSettle();
    expect(find.text('Ya existe una sala con ese nombre.'), findsOneWidget);
  });

  testWidgets('Se agrega un equipo a una sala', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final room = Room('Sala piloto', []);
    var changes = 0;
    await tester.pumpWidget(_room(room, onChanged: () => changes++));

    await tester.tap(find.text('Agregar equipo').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Ej. Switch principal Cisco'),
        'Servidor NAS');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Ej. SW-R1-03'), 'NAS-01');
    await tester.tap(find.text('Servidor'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(FilledButton, 'Agregar equipo')));
    await tester.pumpAndSettle();

    expect(room.assets.length, 1);
    expect(room.assets.single.code, 'NAS-01');
    expect(room.assets.single.type, 'Servidor');
    // The picked type sets a matching icon by default.
    expect(room.assets.single.icon, DeviceIcon.server);
    expect(changes, 1);
    // The new asset is selected and its detail is shown.
    expect(find.text('Servidor NAS'), findsWidgets);
  });

  testWidgets('Se cambia el ícono de un equipo desde su ficha', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final asset = Asset(
        'PC-01', 'Equipo piloto', 'Computador', const Offset(.3, .3),
        icon: DeviceIcon.computer);
    await tester.pumpWidget(_room(Room('Sala piloto', [asset])));

    await tester.tap(find.byType(Marker));
    await tester.pumpAndSettle();
    // The icon picker exposes each option by its label.
    await tester.tap(find.bySemanticsLabel('Portátil'));
    await tester.pumpAndSettle();
    expect(asset.icon, DeviceIcon.laptop);
  });
}
