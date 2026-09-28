import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yankees/core/network/api_client.dart';
import 'package:yankees/core/session/session_manager.dart';
import 'package:yankees/core/session/session_store.dart';
import 'package:yankees/features/auth/data/app_user.dart';

const _user = AppUser(
  id: 'u1',
  email: 'ana@test.com',
  firstName: 'Ana',
  firstLastName: 'Gómez',
  role: UserRole.parent,
);

void main() {
  late DateTime now;
  late List<http.Request> requests;
  late MemorySessionStore store;
  late ApiClient api;
  late SessionManager session;
  late int refreshCount;

  /// Respuestas: refresh rota tokens (rt-N → rt-N+1); /api/datos devuelve
  /// 401 si el token no es el vigente.
  void setUpApi({
    http.Response Function(http.Request)? refresh,
    String validToken = 'at-1',
  }) {
    requests = [];
    refreshCount = 0;
    var currentAccess = validToken;
    final client = MockClient((req) async {
      requests.add(req);
      if (req.url.path == '/api/Session/refresh-token') {
        if (refresh != null) return refresh(req);
        refreshCount++;
        currentAccess = 'at-${refreshCount + 1}';
        return http.Response(
          jsonEncode({
            'responseCode': '00',
            'sessionToken': currentAccess,
            'refreshToken': 'rt-${refreshCount + 1}',
            'expiresIn': 60,
          }),
          200,
        );
      }
      if (req.url.path == '/api/Session/logout') {
        return http.Response(jsonEncode({'responseCode': '00'}), 200);
      }
      final ok = req.headers['Authorization'] == 'Bearer $currentAccess';
      return ok
          ? http.Response(jsonEncode({'ok': true}), 200)
          : http.Response(
              jsonEncode({
                'responseCode': '05',
                'message': 'AUTENTICACION INVALIDA',
              }),
              401,
            );
    });
    api = ApiClient(baseUrl: 'http://api.test', client: client);
    store = MemorySessionStore();
    session = SessionManager(api: api, store: store, clock: () => now);
    api.authenticator = session;
  }

  Future<void> startSession({int expiresIn = 60}) => session.start(
    user: _user,
    accessToken: 'at-1',
    refreshToken: 'rt-1',
    expiresIn: expiresIn,
  );

  setUp(() => now = DateTime(2026, 9, 27, 12));

  test('con token vigente no renueva', () async {
    setUpApi();
    await startSession();
    await api.post('/api/datos', {});
    expect(refreshCount, 0);
    expect(requests.single.headers['Authorization'], 'Bearer at-1');
  });

  test('renueva antes de vencer y guarda el refresh token rotado', () async {
    setUpApi();
    await startSession();
    now = now.add(const Duration(seconds: 45)); // faltan 15 s (< margen 30)

    await api.post('/api/datos', {});

    expect(refreshCount, 1);
    expect(jsonDecode(requests.first.body), {'refreshToken': 'rt-1'});
    expect(requests.first.headers.containsKey('Authorization'), isFalse);
    expect(requests.last.headers['Authorization'], 'Bearer at-2');
    expect(store.session!.refreshToken, 'rt-2');
    expect(store.session!.accessToken, 'at-2');
  });

  test('si la API responde 401 renueva y reintenta una vez', () async {
    setUpApi(validToken: 'at-2'); // el servidor ya no acepta at-1
    await startSession();

    final json = await api.post('/api/datos', {});

    expect(json, {'ok': true});
    expect(refreshCount, 1);
    expect(requests.map((r) => r.url.path), [
      '/api/datos',
      '/api/Session/refresh-token',
      '/api/datos',
    ]);
  });

  test('varios requests a la vez comparten una sola renovación', () async {
    setUpApi();
    await startSession();
    now = now.add(const Duration(minutes: 5));

    await Future.wait([
      api.post('/api/datos', {}),
      api.post('/api/datos', {}),
      api.post('/api/datos', {}),
    ]);

    expect(refreshCount, 1);
  });

  test('refresh rechazado cierra la sesión y avisa', () async {
    setUpApi(
      refresh: (_) => http.Response(
        jsonEncode({
          'responseCode': '05',
          'message': 'REFRESH_TOKEN INVALIDO O REVOCADO',
        }),
        401,
      ),
    );
    var expired = false;
    session.onSessionExpired = () => expired = true;
    await startSession();
    now = now.add(const Duration(minutes: 5));

    expect(await session.accessToken(), isNull);
    expect(expired, isTrue);
    expect(store.session, isNull);
    expect(session.currentUser, isNull);
  });

  test('sin conexión no cierra la sesión', () async {
    setUpApi(refresh: (_) => throw http.ClientException('offline'));
    var expired = false;
    session.onSessionExpired = () => expired = true;
    await startSession();
    now = now.add(const Duration(minutes: 5));

    expect(await session.accessToken(), isNull);
    expect(expired, isFalse);
    expect(store.session, isNotNull);
  });

  group('restore', () {
    test('sin sesión guardada devuelve null', () async {
      setUpApi();
      expect(await session.restore(), isNull);
      expect(requests, isEmpty);
    });

    test('sesión vigente se recupera sin llamar a la API', () async {
      setUpApi();
      await startSession(expiresIn: 3600);
      final restored = SessionManager(api: api, store: store, clock: () => now);

      expect((await restored.restore())!.email, 'ana@test.com');
      expect(requests, isEmpty);
    });

    test('sesión vencida se renueva al abrir la app', () async {
      setUpApi();
      await startSession();
      now = now.add(const Duration(hours: 3));
      final restored = SessionManager(api: api, store: store, clock: () => now);

      expect(await restored.restore(), isNotNull);
      expect(refreshCount, 1);
      expect(store.session!.refreshToken, 'rt-2');
    });

    test('refresh revocado al abrir la app manda al login', () async {
      setUpApi(
        refresh: (_) => http.Response(
          jsonEncode({'responseCode': '05', 'message': 'REVOCADO'}),
          401,
        ),
      );
      await startSession();
      now = now.add(const Duration(hours: 3));
      final restored = SessionManager(api: api, store: store, clock: () => now);

      expect(await restored.restore(), isNull);
      expect(store.session, isNull);
    });
  });

  test('end revoca en la API y borra local; sin red igual borra', () async {
    setUpApi();
    await startSession();
    await session.end();
    expect(requests.single.url.path, '/api/Session/logout');
    expect(store.session, isNull);

    setUpApi();
    await startSession();
    final offline = SessionManager(
      api: ApiClient(
        baseUrl: 'http://api.test',
        client: MockClient((_) => throw http.ClientException('offline')),
      ),
      store: store,
    );
    await offline.restore();
    await offline.end();
    expect(store.session, isNull);
  });
}
