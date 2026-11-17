import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_ti/csv_import.dart';
import 'package:inventario_ti/inventory_data.dart';

void main() {
  test('parses rows, maps icon and status, fills defaults', () {
    const csv = 'codigo,nombre,tipo,icono,responsable,estado\n'
        'SW-1,Switch core,Switch,switch,Soporte TI,operational\n'
        'PC-1,PC recepción,Computador,,,\n';
    final result = parseAssetsCsv(csv);
    expect(result.errors, isEmpty);
    expect(result.assets, hasLength(2));

    final sw = result.assets[0];
    expect(sw.code, 'SW-1');
    expect(sw.icon, DeviceIcon.networkSwitch);
    expect(sw.responsible, 'Soporte TI');
    expect(sw.status, AssetStatus.operational);

    final pc = result.assets[1];
    // Icon falls back from the type; status defaults to unknown.
    expect(pc.icon, DeviceIcon.computer);
    expect(pc.status, AssetStatus.unknown);
    expect(pc.responsible, '');
  });

  test('accepts Spanish labels and header order, ignores accents', () {
    const csv = 'Nombre,Código,Tipo,Estado\n'
        'Router fibra,RT-1,Router,En mantenimiento\n';
    final result = parseAssetsCsv(csv);
    expect(result.assets.single.code, 'RT-1');
    expect(result.assets.single.status, AssetStatus.maintenance);
    expect(result.assets.single.icon, DeviceIcon.router);
  });

  test('reports missing required columns', () {
    const csv = 'nombre,tipo\nAlgo,Switch\n';
    final result = parseAssetsCsv(csv);
    expect(result.assets, isEmpty);
    expect(result.errors, isNotEmpty);
  });

  test('flags rows missing required values', () {
    const csv = 'codigo,nombre,tipo\n,Sin código,Switch\nOK-1,Bien,Router\n';
    final result = parseAssetsCsv(csv);
    expect(result.assets, hasLength(1));
    expect(result.assets.single.code, 'OK-1');
    expect(result.errors, hasLength(1));
  });

  test('handles quoted fields with commas', () {
    const csv = 'codigo,nombre,tipo\n'
        'SRV-1,"Servidor, principal",Servidor\n';
    final result = parseAssetsCsv(csv);
    expect(result.assets.single.name, 'Servidor, principal');
  });

  test('template parses back cleanly', () {
    final result = parseAssetsCsv(assetsCsvTemplate());
    expect(result.errors, isEmpty);
    expect(result.assets, hasLength(1));
  });
}
