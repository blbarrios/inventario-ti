import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventario_ti/auth_gate.dart';
import 'package:inventario_ti/auth_session.dart';

void main() {
  test('La sesión nativa envía el token y detecta su caducidad', () async {
    var expired = false;
    final session = AuthSession(
      base: 'http://localhost/api',
      client: MockClient((request) async {
        expect(request.headers['x-inventory-request'], '1');
        if (request.url.path.endsWith('/login')) {
          return http.Response(
              jsonEncode({
                'user': {'username': 'tecnico'},
                'token': 'session-token',
              }),
              200);
        }
        expect(request.headers['authorization'], 'Bearer session-token');
        return http.Response('{"error":"Tu sesión terminó"}', 401);
      }),
    );
    addTearDown(session.dispose);
    await session.login('tecnico', 'password');
    session.addListener(() {
      if (session.user == null) expired = true;
    });
    await session.client.get(Uri.parse('http://localhost/api/rooms'));
    expect(expired, true);
    expect(session.client.token, isNull);
  });

  testWidgets('El acceso permite corregir la contraseña y muestra errores',
      (tester) async {
    var attempts = 0;
    final session = AuthSession(
      base: 'http://localhost/api',
      client: MockClient((request) async {
        attempts++;
        expect(jsonDecode(request.body)['username'], 'tecnico');
        return http.Response(
            '{"error":"Usuario o contraseña incorrectos"}', 401);
      }),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(home: LoginPage(session: session)));
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    expect(find.text('Escribe tu usuario'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'tecnico');
    await tester.enterText(find.byType(TextFormField).last, 'incorrecta');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    expect(find.text('Usuario o contraseña incorrectos'), findsOneWidget);
    expect(find.text('tecnico'), findsOneWidget);
    expect(attempts, 1);
  });
}
