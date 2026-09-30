import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yankees/core/network/api_client.dart';
import 'package:yankees/core/session/session_manager.dart';
import 'package:yankees/core/session/session_store.dart';
import 'package:yankees/features/auth/data/api_auth_repository.dart';
import 'package:yankees/features/auth/data/auth_repository.dart';
import 'package:yankees/features/auth/data/google_id_token_provider.dart';
import 'package:yankees/features/billing/data/billing_models.dart';

class _FakeGoogle implements GoogleIdTokenProvider {
  _FakeGoogle(this.token);
  final String? token;
  bool signedOut = false;

  @override
  Future<String?> getIdToken() async => token;

  @override
  Future<void> signOut() async => signedOut = true;
}

class _ThrowingGoogle implements GoogleIdTokenProvider {
  @override
  Future<String?> getIdToken() => throw Exception('[16] Account reauth failed');

  @override
  Future<void> signOut() async {}
}

void main() {
  late List<http.Request> requests;
  late ApiClient api;
  late MemorySessionStore store;

  ApiAuthRepository repo(
    http.Response Function(http.Request) handler, {
    String? googleToken = 'id-token-123',
  }) {
    requests = [];
    final client = MockClient((req) async {
      requests.add(req);
      return handler(req);
    });
    api = ApiClient(baseUrl: 'http://api.test', client: client);
    store = MemorySessionStore();
    final session = SessionManager(api: api, store: store);
    api.authenticator = session;
    return ApiAuthRepository(
      api: api,
      session: session,
      google: _FakeGoogle(googleToken),
      pending: MockAuthRepository(),
    );
  }

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, dynamic> sentBody([int i = 0]) =>
      jsonDecode(requests[i].body) as Map<String, dynamic>;

  Map<String, dynamic> tokens(String access, String refresh) => {
    'accessToken': access,
    'refreshToken': refresh,
    'expiresIn': 3600,
    'tokenType': 'Bearer',
  };

  Map<String, dynamic> loginOk() => {
    'responseCode': '00',
    'responseMessage': 'OPERACION EXITOSA',
    'userData': {
      'userId': 'abc123',
      'email': 'ana@test.com',
      'authenticationMethod': 'password',
    },
    'tokenData': tokens('jwt-pw', 'rt-pw'),
  };

  Map<String, dynamic> profileOk() => {
    'responseCode': '00',
    'responseMessage': 'PERFIL OBTENIDO',
    'userData': {
      'userId': 'abc123',
      'email': 'ana@test.com',
      'firstName': 'Ana',
      'firstLastName': 'Gómez',
    },
  };

  group('register', () {
    test('envía ManageUser y usa la sesión que devuelve', () async {
      final r = repo(
        (_) => json({
          'typeOperation': 'A',
          'responseCode': '00',
          'responseMessage': 'SUCCESS ADDED',
          'userData': {
            'userId': 'abc123',
            'email': 'ana@test.com',
            'firstName': 'Ana',
            'firstLastName': 'Gómez',
          },
          'tokenData': tokens('jwt-reg', 'rt-reg'),
        }),
      );

      final user = await r.register(
        email: ' Ana@Test.com ',
        firstName: ' Ana ',
        firstLastName: 'Gómez',
        password: 'clave123',
      );

      expect(requests.first.method, 'POST');
      expect(
        requests.first.url.toString(),
        'http://api.test/api/User/ManageUser',
      );
      expect(sentBody(), {
        'typeOperation': 'A',
        'userData': {
          'username': 'ana',
          'email': 'ana@test.com',
          'password': 'clave123',
          'firstName': 'Ana',
          'firstLastName': 'Gómez',
        },
      });
      expect(user.id, 'abc123');
      expect(user.fullName, 'Ana Gómez');
      expect(store.session!.accessToken, 'jwt-reg');
      // Después pide /me para traer rol y permisos.
      expect(requests.last.url.path, '/api/User/me');
      expect(store.session!.refreshToken, 'rt-reg');
    });

    test('si el registro no trae sesión, entra con las credenciales', () async {
      final r = repo(
        (req) => req.url.path == '/api/Auth/signin-password'
            ? json(loginOk())
            : json({
                'responseCode': '00',
                'userData': {'userId': 'abc123'},
              }),
      );
      final user = await r.register(
        email: 'ana@test.com',
        firstName: 'Ana',
        firstLastName: 'Gómez',
        password: 'clave123',
      );
      expect(requests.map((r) => r.url.path), [
        '/api/User/ManageUser',
        '/api/Auth/signin-password',
        '/api/User/me',
      ]);
      expect(user.fullName, 'Ana Gómez');
      expect(store.session!.accessToken, 'jwt-pw');
    });

    test('si tampoco puede entrar, la cuenta igual queda creada', () async {
      final r = repo(
        (req) => req.url.path == '/api/Auth/signin-password'
            ? json({'responseCode': '96', 'message': 'X'}, 500)
            : json({
                'responseCode': '00',
                'userData': {'userId': 'abc123'},
              }),
      );
      final user = await r.register(
        email: 'ana@test.com',
        firstName: 'Ana',
        firstLastName: 'Gómez',
        password: 'clave123',
      );
      expect(user.id, 'abc123');
      expect(store.session, isNull);
    });

    test('responseCode distinto de 00 con HTTP 200 es error', () async {
      final r = repo(
        (_) => json({
          'responseCode': '10',
          'responseMessage': 'EL CORREO YA SE ENCUENTRA REGISTRADO',
        }),
      );
      expect(
        () => r.register(
          email: 'a@t.com',
          firstName: 'A',
          firstLastName: 'B',
          password: 'clave123',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'El correo ya se encuentra registrado',
          ),
        ),
      );
    });

    test('error 500 muestra mensaje genérico', () async {
      final r = repo(
        (_) => json({
          'responseCode': '96',
          'message': 'Error al procesar tu solicitud, contacta a soporte.',
        }, 500),
      );
      expect(
        () => r.register(
          email: 'a@t.com',
          firstName: 'A',
          firstLastName: 'B',
          password: 'clave123',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('error en el servidor'),
          ),
        ),
      );
    });

    test('sin conexión da un mensaje claro', () async {
      final r = repo((_) => throw http.ClientException('refused'));
      expect(
        () => r.register(
          email: 'a@t.com',
          firstName: 'A',
          firstLastName: 'B',
          password: 'clave123',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('No se pudo conectar'),
          ),
        ),
      );
    });
    test('correo duplicado (código 26) se muestra en español', () async {
      final r = repo(
        (_) => json({
          'responseCode': '26',
          'message': 'USERNAME ALREADY EXISTS,EMAIL ALREADY EXISTS',
        }, 400),
      );
      expect(
        () => r.register(
          email: 'a@t.com',
          firstName: 'A',
          firstLastName: 'B',
          password: 'clave123',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Ya existe una cuenta con ese correo.',
          ),
        ),
      );
    });
  });

  group('signIn (correo y contraseña)', () {
    test('abre sesión y completa el nombre con /api/User/me', () async {
      final r = repo(
        (req) => req.url.path == '/api/User/me'
            ? json(profileOk())
            : json(loginOk()),
      );
      final user = await r.signIn(email: ' Ana@Test.com ', password: 'x1y2z3');

      expect(requests.first.url.path, '/api/Auth/signin-password');
      expect(requests.first.headers.containsKey('Authorization'), isFalse);
      expect(sentBody(), {'email': 'ana@test.com', 'password': 'x1y2z3'});
      expect(requests.last.method, 'GET');
      expect(requests.last.url.path, '/api/User/me');
      expect(requests.last.headers['Authorization'], 'Bearer jwt-pw');
      expect(user.id, 'abc123');
      expect(user.displayName, 'Ana Gómez');
      expect(store.session!.refreshToken, 'rt-pw');
      expect(store.session!.user.fullName, 'Ana Gómez');
    });

    test('/me trae el perfil de cobro y se guarda en la sesión', () async {
      final r = repo(
        (req) => req.url.path == '/api/User/me'
            ? json({
                ...profileOk(),
                'access': {
                  'roleName': 'USER_BASE',
                  'permissions': ['hijos.gestionar_propios'],
                },
                'billing': {
                  'status': 'P',
                  'enrollmentFee': null,
                  'monthlyFee': null,
                  'solvent': true,
                  'overdueAmount': 0,
                },
              })
            : json(loginOk()),
      );
      final user = await r.signIn(email: 'ana@test.com', password: 'x1y2z3');
      expect(user.billing!.status, BillingStatus.pending);
      expect(user.awaitingValidation, isTrue);
      expect(store.session!.user.billing!.status, BillingStatus.pending);

      // Una vez validado, /me lo refleja y ya no espera.
      final validated = repo(
        (req) => req.url.path != '/api/User/me'
            ? json(loginOk())
            : json({
                ...profileOk(),
                'access': {
                  'roleName': 'USER_BASE',
                  'permissions': ['hijos.gestionar_propios'],
                },
                'billing': {
                  'status': 'A',
                  'enrollmentFee': 250.0,
                  'monthlyFee': 150.0,
                  'solvent': false,
                  'overdueAmount': 150.0,
                },
              }),
      );
      final u2 = await validated.signIn(email: 'ana@test.com', password: 'x');
      expect(u2.awaitingValidation, isFalse);
      expect(u2.billing!.monthlyFee, 150);
      expect(u2.billing!.solvent, isFalse);
      expect(u2.billing!.overdueAmount, 150);
    });

    test('si /me falla igual entra y muestra el correo', () async {
      final r = repo(
        (req) => req.url.path == '/api/User/me'
            ? json({'responseCode': '96', 'message': 'X'}, 500)
            : json(loginOk()),
      );
      final user = await r.signIn(email: 'ana@test.com', password: 'x1y2z3');
      expect(user.displayName, 'ana@test.com');
      expect(store.session, isNotNull);
    });

    test('credenciales inválidas (401) da mensaje claro', () async {
      final r = repo(
        (_) => json({
          'responseCode': '05',
          'message': 'CREDENCIALES INVALIDAS',
        }, 401),
      );
      expect(
        () => r.signIn(email: 'a@t.com', password: 'mala123'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Correo o contraseña incorrectos',
          ),
        ),
      );
    });

    test('demasiados intentos (429) avisa esperar', () async {
      final r = repo((_) => http.Response('', 429));
      expect(
        () => r.signIn(email: 'a@t.com', password: 'clave123'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Demasiados intentos'),
          ),
        ),
      );
    });
  });

  group('perfil', () {
    test(
      'updateProfile manda U con el userId de la sesión y relee /me',
      () async {
        final r = repo((req) {
          if (req.url.path == '/api/User/me') {
            return json({
              'responseCode': '00',
              'userData': {
                'userId': 'abc123',
                'email': 'ana@test.com',
                'firstName': 'Ana',
                'secondName': 'María',
                'firstLastName': 'Gómez',
              },
            });
          }
          if (req.url.path == '/api/User/ManageUser') {
            return json({
              'responseCode': '00',
              'responseMessage': 'USER UPDATED SUCCESSFULLY',
            });
          }
          return json(loginOk());
        });
        await r.signIn(email: 'ana@test.com', password: 'clave123');
        requests.clear();

        final user = await r.updateProfile(
          const ProfileInput(
            firstName: 'Ana',
            secondName: 'María',
            firstLastName: 'Gómez',
            secondLastName: '',
          ),
        );

        expect(requests.first.url.path, '/api/User/ManageUser');
        expect(requests.first.headers['Authorization'], 'Bearer jwt-pw');
        expect(sentBody(), {
          'typeOperation': 'U',
          'userData': {
            'userId': 'abc123',
            'firstName': 'Ana',
            'secondName': 'María',
            'firstLastName': 'Gómez',
          },
        });
        expect(requests.last.url.path, '/api/User/me');
        expect(user.legalName, 'Ana María Gómez');
        expect(store.session!.user.secondName, 'María');
      },
    );

    test('sin sesión no intenta actualizar', () async {
      final r = repo((_) => json({}));
      expect(
        () => r.updateProfile(
          const ProfileInput(firstName: 'A', firstLastName: 'B'),
        ),
        throwsA(isA<AuthException>()),
      );
      expect(requests, isEmpty);
    });
  });

  group('signInWithGoogle', () {
    Map<String, dynamic> googleOk({
      String? givenName = 'María José',
      String? familyName = 'López',
    }) => {
      'typeOperation': 'A',
      'responseCode': '00',
      'responseMessage': 'OPERACION EXITOSA',
      'userData': {
        'userId': 'db-42',
        'sub': '1098',
        'email': 'maria@gmail.com',
        'email_verified': true,
        'name': 'María José López',
        'picture': 'https://x/p.png',
        'given_name': givenName,
        'family_name': familyName,
      },
      'authenticationMethod': 'google',
      'tokenData': tokens('jwt-abc', 'rt-1'),
    };

    test('manda el idToken y mapea el usuario de Google', () async {
      final r = repo((_) => json(googleOk()));

      final user = await r.signInWithGoogle();

      expect(requests.first.url.path, '/api/GoogleAuth/signin-google');
      expect(sentBody(), {
        'typeOperation': 'A',
        'googleData': {'idToken': 'id-token-123'},
      });
      expect(user!.id, 'db-42');
      expect(user.email, 'maria@gmail.com');
      expect(user.firstName, 'María José');
      expect(user.firstLastName, 'López');
    });

    test('sin given/family name parte el nombre completo', () async {
      final r = repo((_) => json(googleOk(givenName: null, familyName: null)));
      final user = await r.signInWithGoogle();
      expect(user!.firstName, 'María');
      expect(user.firstLastName, 'José López');
    });

    test('guarda la sesión, manda el token y al salir la revoca', () async {
      final r = repo((_) => json(googleOk()));
      await r.signInWithGoogle();
      expect(store.session!.accessToken, 'jwt-abc');
      expect(store.session!.refreshToken, 'rt-1');
      expect(store.session!.user.email, 'maria@gmail.com');

      await api.post('/api/otra', {});
      expect(requests.last.headers['Authorization'], 'Bearer jwt-abc');

      await r.signOut();
      expect(store.session, isNull);
      expect(requests.last.url.path, '/api/Session/logout');
      expect(jsonDecode(requests.last.body), {'refreshToken': 'rt-1'});
    });

    test('login y registro no mandan Authorization', () async {
      final r = repo((_) => json(googleOk()));
      await r.signInWithGoogle();
      expect(requests.first.headers.containsKey('Authorization'), isFalse);
    });

    test('respuesta sin refresh token es error', () async {
      final r = repo(
        (_) => json(googleOk()..['tokenData'] = {'accessToken': 'jwt-abc'}),
      );
      expect(
        r.signInWithGoogle,
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            ApiAuthRepository.googleErrorMessage,
          ),
        ),
      );
    });

    test('si el usuario cancela no llama a la API', () async {
      final r = repo((_) => json({}), googleToken: null);
      expect(await r.signInWithGoogle(), isNull);
      expect(requests, isEmpty);
    });

    test('token rechazado (401) da el mensaje genérico de Google', () async {
      final r = repo(
        (_) => json({
          'responseCode': '05',
          'message': 'ID_TOKEN DE GOOGLE INVALIDO O EXPIRADO',
        }, 401),
      );
      expect(
        r.signInWithGoogle,
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            ApiAuthRepository.googleErrorMessage,
          ),
        ),
      );
    });

    test('falla del SDK de Google da el mensaje genérico', () async {
      requests = [];
      api = ApiClient(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => http.Response('', 200)),
      );
      final r = ApiAuthRepository(
        api: api,
        session: SessionManager(api: api, store: MemorySessionStore()),
        google: _ThrowingGoogle(),
        pending: MockAuthRepository(),
      );
      expect(
        r.signInWithGoogle,
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            ApiAuthRepository.googleErrorMessage,
          ),
        ),
      );
    });
  });

  group('username para la API (sin @)', () {
    test('se toma la parte antes de la arroba', () {
      expect(
        ApiAuthRepository.usernameFor(' Juan.Perez@Gmail.com '),
        'juan.perez',
      );
      expect(ApiAuthRepository.usernameFor('${'a' * 60}@x.com'), hasLength(50));
    });

    test('si ya existe, reintenta con un sufijo', () async {
      var calls = 0;
      final r = repo((req) {
        if (req.url.path == '/api/User/ManageUser' && calls++ == 0) {
          return json({
            'responseCode': '39',
            'message': 'USERNAME ALREADY EXISTS',
          }, 400);
        }
        if (req.url.path == '/api/User/me') {
          return json({'responseCode': '00', 'userData': {}});
        }
        return json({
          'responseCode': '00',
          'userData': {'userId': 'u2', 'email': 'juan@hotmail.com'},
          'tokenData': tokens('a', 'b'),
        });
      });
      await r.register(
        email: 'juan@hotmail.com',
        firstName: 'Juan',
        firstLastName: 'Pérez',
        password: 'clave123',
      );
      final first = (sentBody(0)['userData'] as Map)['username'];
      final second = (sentBody(1)['userData'] as Map)['username'] as String;
      expect(first, 'juan');
      expect(second, matches(RegExp(r'^juan\d{4}$')));
    });

    test('si el correo ya existe no reintenta', () async {
      final r = repo(
        (_) => json({
          'responseCode': '39',
          'message': 'EMAIL ALREADY EXISTS',
        }, 400),
      );
      await expectLater(
        r.register(
          email: 'ana@test.com',
          firstName: 'Ana',
          firstLastName: 'Gómez',
          password: 'clave123',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(requests, hasLength(1));
    });
  });

  test('splitFullName', () {
    expect(ApiAuthRepository.splitFullName('Ana'), ('Ana', ''));
    expect(ApiAuthRepository.splitFullName('  '), ('', ''));
    expect(ApiAuthRepository.splitFullName('Juan Carlos Pérez'), (
      'Juan',
      'Carlos Pérez',
    ));
  });
}
