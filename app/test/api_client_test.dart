import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventario_ti/inventory_data.dart';
import 'package:inventario_ti/inventory_repository.dart';

HttpInventoryRepository repoWith(MockClient client) =>
    HttpInventoryRepository(base: '/api', client: client);

void main() {
  test('loadRooms fetches each room detail and maps assets', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/rooms') {
        return http.Response(
            jsonEncode([
              {'id': 'r1', 'name': 'Sala 1'}
            ]),
            200);
      }
      if (request.url.path == '/api/rooms/r1') {
        return http.Response(
            jsonEncode({
              'id': 'r1',
              'name': 'Sala 1',
              'layout_version': 3,
              'assets': [
                {
                  'id': 'a1',
                  'code': 'SW-1',
                  'name': 'Switch',
                  'type': 'Switch',
                  'status': 'faulty',
                  'status_version': 2,
                  'icon': 'switch',
                  'x': 0.25,
                  'y': 0.4,
                },
                {
                  'id': 'a2',
                  'code': 'PC-1',
                  'name': 'PC',
                  'type': 'Computador',
                  'status': 'unknown',
                  'status_version': 1,
                  'icon': 'computer',
                  'x': null,
                  'y': null,
                },
              ],
            }),
            200);
      }
      return http.Response('not found', 404);
    });

    final rooms = await repoWith(client).loadRooms();
    expect(rooms, hasLength(1));
    final room = rooms.single;
    expect(room.id, 'r1');
    expect(room.layoutVersion, 3);
    expect(room.assets, hasLength(2));

    final sw = room.assets.firstWhere((a) => a.code == 'SW-1');
    expect(sw.status, AssetStatus.faulty);
    expect(sw.statusVersion, 2);
    expect(sw.icon, DeviceIcon.networkSwitch);
    expect(sw.hasPosition, isTrue);
    expect(sw.position, const Offset(0.25, 0.4));

    // An asset with no stored position is given a cascade spot.
    final pc = room.assets.firstWhere((a) => a.code == 'PC-1');
    expect(pc.hasPosition, isFalse);
  });

  test('createRoom posts the name and maps the new room', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
          jsonEncode({'id': 'r9', 'name': 'Bodega', 'layout_version': 1}), 201);
    });
    final room = await repoWith(client).createRoom('Bodega');
    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/rooms');
    expect(jsonDecode(seen.body), {'name': 'Bodega'});
    expect(room.id, 'r9');
    expect(room.name, 'Bodega');
  });

  test('createRoom surfaces a duplicate name as a friendly error', () async {
    final client = MockClient((request) async =>
        http.Response(jsonEncode({'error': 'duplicado'}), 409));
    await expectLater(
      repoWith(client).createRoom('Sala 1'),
      throwsA(
          isA<ApiException>().having((e) => e.duplicate, 'duplicate', isTrue)),
    );
  });

  test('createAsset sends the icon key and keeps the given position', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
          jsonEncode({
            'id': 'a5',
            'code': 'RT-1',
            'name': 'Router',
            'type': 'Router',
            'status': 'unknown',
            'status_version': 1,
            'icon': 'router',
          }),
          201);
    });
    final room = Room('Sala 1', [], id: 'r1');
    final asset = await repoWith(client).createAsset(
      room,
      code: 'RT-1',
      name: 'Router',
      type: 'Router',
      icon: DeviceIcon.router,
      position: const Offset(0.3, 0.6),
    );
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['roomId'], 'r1');
    expect(body['icon'], 'router');
    expect(asset.id, 'a5');
    expect(asset.icon, DeviceIcon.router);
    expect(asset.position, const Offset(0.3, 0.6));
    expect(asset.hasPosition, isFalse); // persisted on the next layout save
  });

  test('updateStatus sends the version and records history', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
          jsonEncode({
            'id': 'a1',
            'code': 'SW-1',
            'name': 'Switch',
            'type': 'Switch',
            'status': 'operational',
            'status_version': 3,
            'icon': 'switch',
          }),
          200);
    });
    final asset = Asset('SW-1', 'Switch', 'Switch', const Offset(.2, .2),
        id: 'a1', status: AssetStatus.faulty, statusVersion: 2);
    await repoWith(client)
        .updateStatus(asset, AssetStatus.operational, 'Reiniciado');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(seen.url.path, '/api/assets/a1/status');
    expect(body['status'], 'operational');
    expect(body['version'], 2);
    expect(asset.status, AssetStatus.operational);
    expect(asset.statusVersion, 3);
    expect(asset.history.first.current, AssetStatus.operational);
  });

  test('updateStatus maps a version clash to a conflict error', () async {
    final client = MockClient(
        (request) async => http.Response(jsonEncode({'error': 'cambió'}), 409));
    final asset = Asset('SW-1', 'Switch', 'Switch', const Offset(.2, .2),
        id: 'a1', statusVersion: 1);
    await expectLater(
      repoWith(client).updateStatus(asset, AssetStatus.operational, ''),
      throwsA(
          isA<ApiException>().having((e) => e.conflict, 'conflict', isTrue)),
    );
  });

  test('updateIcon patches the icon key', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(jsonEncode({'id': 'a1', 'icon': 'laptop'}), 200);
    });
    final asset = Asset('PC-1', 'PC', 'Computador', const Offset(.2, .2),
        id: 'a1', icon: DeviceIcon.computer);
    await repoWith(client).updateIcon(asset, DeviceIcon.laptop);
    expect(seen.url.path, '/api/assets/a1/icon');
    expect(jsonDecode(seen.body), {'icon': 'laptop'});
    expect(asset.icon, DeviceIcon.laptop);
  });

  test('saveLayout sends every position and bumps the version', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(jsonEncode({'layout_version': 5}), 200);
    });
    final room = Room(
        'Sala 1',
        [
          Asset('A', 'A', 'Switch', const Offset(.1, .2), id: 'a1'),
          Asset('B', 'B', 'Router', const Offset(.3, .4), id: 'a2'),
        ],
        id: 'r1',
        layoutVersion: 4);
    await repoWith(client).saveLayout(room);
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(seen.method, 'PUT');
    expect(seen.url.path, '/api/rooms/r1/layout');
    expect(body['version'], 4);
    expect((body['positions'] as List), hasLength(2));
    expect(room.layoutVersion, 5);
    expect(room.assets.every((a) => a.hasPosition), isTrue);
  });
}
