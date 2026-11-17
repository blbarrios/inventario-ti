import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'inventory_repository.dart';

class SessionClient extends http.BaseClient {
  SessionClient(this.inner);
  final http.Client inner;
  String? token;
  VoidCallback? onExpired;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['x-inventory-request'] = '1';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    try {
      final response =
          await inner.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 &&
          !request.url.path.endsWith('/auth/login')) {
        token = null;
        onExpired?.call();
      }
      return response;
    } catch (_) {
      throw ApiException(
          'No se pudo conectar con el servidor. Intenta nuevamente.');
    }
  }

  @override
  void close() => inner.close();
}

class AuthSession extends ChangeNotifier {
  AuthSession({required this.base, http.Client? client})
      : client = SessionClient(client ?? http.Client()) {
    this.client.onExpired = () {
      if (user == null) return;
      user = null;
      notifyListeners();
    };
  }
  final String base;
  final SessionClient client;
  Map<String, dynamic>? user;

  Map<String, dynamic> decode(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(
          body['error'] as String? ?? 'No se pudo completar la solicitud.');
    }
    return body;
  }

  Future<void> restore() async {
    final response = await client.get(Uri.parse('$base/auth/me'));
    if (response.statusCode == 401) return;
    user = decode(response)['user'] as Map<String, dynamic>;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final response = await client.post(
      Uri.parse('$base/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'username': username.trim(),
        'password': password,
        'desktop': !kIsWeb
      }),
    );
    if (response.statusCode == 429) {
      throw ApiException(
          'Demasiados intentos. Espera un minuto antes de volver a ingresar.');
    }
    final body = decode(response);
    client.token = body['token'] as String?;
    user = body['user'] as Map<String, dynamic>;
    notifyListeners();
  }

  Future<void> logout() async {
    final response = await client.post(Uri.parse('$base/auth/logout'));
    decode(response);
    client.token = null;
    user = null;
    notifyListeners();
  }

  @override
  void dispose() {
    client.onExpired = null;
    client.close();
    super.dispose();
  }
}
