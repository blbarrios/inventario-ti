import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'inventory_data.dart';

/// A failure surfaced from the inventory backend, with a message meant for the
/// user. [conflict] marks an optimistic-concurrency clash (someone else changed
/// the same thing); [duplicate] marks a unique-constraint clash (e.g. a code).
class ApiException implements Exception {
  ApiException(this.message, {this.conflict = false, this.duplicate = false});
  final String message;
  final bool conflict;
  final bool duplicate;
  @override
  String toString() => message;
}

/// What the UI talks to. Two implementations: [DemoInventoryRepository] (in
/// memory, offline) and [HttpInventoryRepository] (the Fastify API).
abstract class InventoryRepository {
  Future<List<Room>> loadRooms();
  Future<Room> createRoom(String name);
  Future<Asset> createAsset(
    Room room, {
    required String code,
    required String name,
    required String type,
    required DeviceIcon icon,
    required Offset position,
    String responsible,
  });

  /// Edit an existing asset's textual fields (name, type, responsible).
  Future<void> updateAsset(
    Asset asset, {
    required String name,
    required String type,
    required String responsible,
  });
  Future<void> updateStatus(Asset asset, AssetStatus status, String note);
  Future<void> updateIcon(Asset asset, DeviceIcon icon);

  /// Persist every asset's position for a room (the plan layout).
  Future<void> saveLayout(Room room);

  /// The status history for an asset, newest first.
  Future<List<StatusChange>> loadHistory(Asset asset);
}

/// Spreads markers that have no saved position so they don't stack.
Offset cascadePosition(int index) {
  final col = index % 4;
  final row = (index ~/ 4) % 4;
  return Offset(
      (0.16 + col * 0.22).clamp(0.0, 1.0), (0.18 + row * 0.2).clamp(0.0, 1.0));
}

// ---------------------------------------------------------------------------

/// In-memory data: lets the app run with no backend, and backs the tests.
class DemoInventoryRepository implements InventoryRepository {
  final List<Room> _rooms = demoRooms();

  // A copy so the caller owns its own list; the Room objects are shared, so
  // edits (status, icon, positions) still flow back here.
  @override
  Future<List<Room>> loadRooms() async => List.of(_rooms);

  @override
  Future<Room> createRoom(String name) async {
    final trimmed = name.trim();
    if (_rooms.any((r) => r.name.toLowerCase() == trimmed.toLowerCase())) {
      throw ApiException('Ya existe una sala con ese nombre.', duplicate: true);
    }
    final room = Room(trimmed, []);
    _rooms.add(room);
    return room;
  }

  @override
  Future<Asset> createAsset(
    Room room, {
    required String code,
    required String name,
    required String type,
    required DeviceIcon icon,
    required Offset position,
    String responsible = '',
  }) async {
    if (room.assets
        .any((a) => a.code.toLowerCase() == code.trim().toLowerCase())) {
      throw ApiException('El código del equipo ya existe.', duplicate: true);
    }
    return Asset(code.trim(), name.trim(), type.trim(), position,
        icon: icon, responsible: responsible.trim());
  }

  @override
  Future<void> updateAsset(
    Asset asset, {
    required String name,
    required String type,
    required String responsible,
  }) async {
    asset.name = name.trim();
    asset.type = type.trim();
    asset.responsible = responsible.trim();
  }

  @override
  Future<void> updateStatus(
      Asset asset, AssetStatus status, String note) async {
    asset.updateStatus(status, note);
  }

  @override
  Future<void> updateIcon(Asset asset, DeviceIcon icon) async {
    asset.icon = icon;
  }

  @override
  Future<void> saveLayout(Room room) async {}

  @override
  Future<List<StatusChange>> loadHistory(Asset asset) async => asset.history;
}

// ---------------------------------------------------------------------------

/// Talks to the Fastify API under [base] (e.g. 'http://localhost:3000/api' in
/// local dev, or '/api' when the app is served from the same origin).
class HttpInventoryRepository implements InventoryRepository {
  HttpInventoryRepository({required this.base, http.Client? client})
      : _client = client ?? http.Client();

  final String base;
  final http.Client _client;
  static const _jsonHeaders = {'content-type': 'application/json'};

  Uri _uri(String path) => Uri.parse('$base$path');

  Never _fail(http.Response res) {
    var message = 'No se pudo contactar al servidor (${res.statusCode}).';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] is String) message = body['error'];
    } catch (_) {}
    throw ApiException(message, conflict: res.statusCode == 409);
  }

  Future<http.Response> _get(String path) async {
    try {
      return await _client.get(_uri(path));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('No se pudo conectar con el servidor.');
    }
  }

  @override
  Future<List<Room>> loadRooms() async {
    final res = await _get('/rooms');
    if (res.statusCode != 200) _fail(res);
    final summaries = jsonDecode(res.body) as List;
    final rooms = await Future.wait([
      for (final summary in summaries)
        _loadRoom((summary as Map)['id'] as String),
    ]);
    return rooms;
  }

  Future<Room> _loadRoom(String id) async {
    final res = await _get('/rooms/$id');
    if (res.statusCode != 200) _fail(res);
    final room = Room.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    _placeMissing(room);
    return room;
  }

  /// Give a sensible on-plan spot to assets the server has no position for.
  void _placeMissing(Room room) {
    var index = 0;
    for (final asset in room.assets) {
      if (!asset.hasPosition) asset.position = cascadePosition(index++);
    }
  }

  @override
  Future<Room> createRoom(String name) async {
    final res = await _client.post(_uri('/rooms'),
        headers: _jsonHeaders, body: jsonEncode({'name': name.trim()}));
    if (res.statusCode == 409) {
      throw ApiException('Ya existe una sala con ese nombre.', duplicate: true);
    }
    if (res.statusCode != 201) _fail(res);
    return Room.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<Asset> createAsset(
    Room room, {
    required String code,
    required String name,
    required String type,
    required DeviceIcon icon,
    required Offset position,
    String responsible = '',
  }) async {
    final res = await _client.post(
      _uri('/assets'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'code': code.trim(),
        'name': name.trim(),
        'type': type.trim(),
        'roomId': room.id,
        'icon': icon.key,
        'responsible': responsible.trim(),
      }),
    );
    if (res.statusCode == 409) {
      throw ApiException('El código del equipo ya existe.', duplicate: true);
    }
    if (res.statusCode != 201) _fail(res);
    final asset = Asset.fromJson(jsonDecode(res.body) as Map<String, dynamic>)
      ..position = position
      ..hasPosition = false; // persisted on the next layout save
    return asset;
  }

  @override
  Future<void> updateAsset(
    Asset asset, {
    required String name,
    required String type,
    required String responsible,
  }) async {
    final res = await _client.patch(
      _uri('/assets/${asset.id}'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'name': name.trim(),
        'type': type.trim(),
        'responsible': responsible.trim(),
      }),
    );
    if (res.statusCode != 200) _fail(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    asset.name = body['name'] as String? ?? name.trim();
    asset.type = body['type'] as String? ?? type.trim();
    asset.responsible = body['responsible'] as String? ?? responsible.trim();
  }

  @override
  Future<void> updateStatus(
      Asset asset, AssetStatus status, String note) async {
    final previous = asset.status;
    final res = await _client.patch(
      _uri('/assets/${asset.id}/status'),
      headers: _jsonHeaders,
      body: jsonEncode(
          {'status': status.api, 'version': asset.statusVersion, 'note': note}),
    );
    if (res.statusCode == 409) {
      throw ApiException(
          'Alguien cambió el estado de este equipo. Vuelve a abrirlo.',
          conflict: true);
    }
    if (res.statusCode != 200) _fail(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    asset.status = statusFromApi(body['status'] as String);
    asset.statusVersion = (body['status_version'] as num).toInt();
    if (previous != asset.status) {
      asset.history.insert(
          0, StatusChange(previous, asset.status, note.trim(), DateTime.now()));
    }
  }

  @override
  Future<void> updateIcon(Asset asset, DeviceIcon icon) async {
    final res = await _client.patch(
      _uri('/assets/${asset.id}/icon'),
      headers: _jsonHeaders,
      body: jsonEncode({'icon': icon.key}),
    );
    if (res.statusCode != 200) _fail(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    asset.icon = deviceIconFromKey(body['icon'] as String? ?? icon.key);
  }

  @override
  Future<void> saveLayout(Room room) async {
    final res = await _client.put(
      _uri('/rooms/${room.id}/layout'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'version': room.layoutVersion,
        'positions': [
          for (final asset in room.assets)
            {
              'assetId': asset.id,
              'x': asset.position.dx,
              'y': asset.position.dy
            }
        ],
        'items': [for (final item in room.items) item.toLayoutJson()],
      }),
    );
    if (res.statusCode == 409) {
      throw ApiException('La distribución cambió. Vuelve a abrir la sala.',
          conflict: true);
    }
    if (res.statusCode != 200) _fail(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    room.layoutVersion = (body['layout_version'] as num).toInt();
    for (final asset in room.assets) {
      asset.hasPosition = true;
    }
  }

  @override
  Future<List<StatusChange>> loadHistory(Asset asset) async {
    final res = await _get('/assets/${asset.id}/history');
    if (res.statusCode != 200) _fail(res);
    final rows = jsonDecode(res.body) as List;
    return [
      for (final row in rows)
        StatusChange(
          statusFromApi((row as Map)['previous_status'] as String),
          statusFromApi(row['new_status'] as String),
          row['note'] as String? ?? '',
          DateTime.tryParse(row['changed_at'] as String? ?? '') ??
              DateTime.now(),
        ),
    ];
  }
}

/// Picks the repository for the running app. Opt into the API at build time
/// with --dart-define=USE_API=true (and API_BASE for cross-origin dev).
InventoryRepository defaultRepository() {
  const useApi = bool.fromEnvironment('USE_API', defaultValue: false);
  if (!useApi) return DemoInventoryRepository();
  const apiBase = String.fromEnvironment('API_BASE');
  final base = apiBase.isEmpty ? '/api' : '$apiBase/api';
  return HttpInventoryRepository(base: base);
}
