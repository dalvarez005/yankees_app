import '../../../core/network/api_client.dart';
import '../../../core/session/session_manager.dart';
import 'app_user.dart';
import 'auth_repository.dart';
import 'google_id_token_provider.dart';

/// Implementación contra la API de Yankees.
///
/// Endpoints: registro (`/api/User/ManageUser`), login con correo
/// (`/api/Auth/signin-password`), Google (`/api/GoogleAuth/signin-google`) y
/// la sesión (`/api/Session/*`) que maneja [SessionManager]. Lo que la API
/// aún no tiene (recuperar contraseña) se delega a [pending].
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({
    required ApiClient api,
    required SessionManager session,
    required GoogleIdTokenProvider google,
    required AuthRepository pending,
  }) : _api = api,
       _session = session,
       _google = google,
       _pending = pending;

  // Campos privados con parámetros nombrados públicos.
  // ignore_for_file: prefer_initializing_formals
  final ApiClient _api;
  final SessionManager _session;
  final GoogleIdTokenProvider _google;
  final AuthRepository _pending;

  @override
  Future<AppUser> register({
    required String email,
    required String firstName,
    required String firstLastName,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final json = await _call(
      () => _api.post('/api/User/ManageUser', {
        'typeOperation': 'A',
        'userData': {
          // La cuenta se identifica por correo: user_name = email.
          'username': normalizedEmail,
          'email': normalizedEmail,
          'password': password,
          'firstName': firstName.trim(),
          'firstLastName': firstLastName.trim(),
        },
      }, authenticated: false),
    );
    _ensureSuccess(json, fallback: 'No se pudo crear la cuenta.');

    final data = json['userData'] as Map<String, dynamic>? ?? const {};
    final user = AppUser(
      id: data['userId']?.toString() ?? '',
      email: data['email']?.toString() ?? normalizedEmail,
      firstName: _nonEmpty(data['firstName']) ?? firstName.trim(),
      firstLastName: _nonEmpty(data['firstLastName']) ?? firstLastName.trim(),
      role: UserRole.parent,
    );

    // La API abre la sesión al registrar. Si no la devolviera, se entra con
    // las mismas credenciales; si eso falla, la cuenta igual quedó creada.
    if (json['tokenData'] is Map<String, dynamic>) {
      await _startSession(user, json, fallback: 'No se pudo crear la cuenta.');
      return user;
    }
    try {
      return await _passwordLogin(normalizedEmail, password, known: user);
    } on AuthException {
      return user;
    }
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) =>
      _passwordLogin(email.trim().toLowerCase(), password);

  Future<AppUser> _passwordLogin(
    String email,
    String password, {
    AppUser? known,
  }) async {
    final Map<String, dynamic> json;
    try {
      json = await _api.post('/api/Auth/signin-password', {
        'username': email,
        'password': password,
      }, authenticated: false);
    } on ApiException catch (e) {
      throw AuthException(
        e.code == '05' || e.statusCode == 401
            ? 'Correo o contraseña incorrectos'
            : e.message,
      );
    }
    _ensureSuccess(json, fallback: 'No se pudo iniciar sesión.');

    final data = json['userData'] as Map<String, dynamic>? ?? const {};
    final user =
        known ??
        AppUser(
          id: data['userId']?.toString() ?? '',
          email: data['email']?.toString() ?? email,
          firstName: '',
          firstLastName: '',
          role: UserRole.parent,
        );
    await _startSession(user, json, fallback: 'No se pudo iniciar sesión.');

    // El login no trae el nombre: se pide el perfil (ya con sesión).
    return known ?? await _withProfile(user);
  }

  /// Completa nombre y apellido con el perfil. Si falla, se sigue con lo
  /// que se tiene (la app muestra el correo).
  Future<AppUser> _withProfile(AppUser user) async {
    try {
      return await fetchProfile();
    } on AuthException {
      return user;
    }
  }

  @override
  Future<AppUser> fetchProfile() async {
    final current = _session.currentUser;
    final json = await _call(() => _api.get('/api/User/me'));
    _ensureSuccess(json, fallback: 'No se pudo cargar tu perfil.');
    final data = json['userData'] as Map<String, dynamic>? ?? const {};
    final user = AppUser(
      id: _nonEmpty(data['userId']) ?? current?.id ?? '',
      email: _nonEmpty(data['email']) ?? current?.email ?? '',
      firstName: _nonEmpty(data['firstName']) ?? current?.firstName ?? '',
      secondName: _nonEmpty(data['secondName']),
      firstLastName:
          _nonEmpty(data['firstLastName']) ?? current?.firstLastName ?? '',
      secondLastName: _nonEmpty(data['secondLastName']),
      role: current?.role ?? UserRole.parent,
    );
    await _session.updateUser(user);
    return user;
  }

  /// `ManageUser` con `U`: la API solo deja modificar al propio usuario
  /// (userId del token). Los campos vacíos no se envían: la API conserva
  /// el valor anterior.
  @override
  Future<AppUser> updateProfile(ProfileInput input) async {
    final userId = _session.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw const AuthException('Tu sesión expiró. Inicia sesión de nuevo.');
    }
    String? opt(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final json = await _call(
      () => _api.post('/api/User/ManageUser', {
        'typeOperation': 'U',
        'userData': {
          'userId': userId,
          'firstName': input.firstName.trim(),
          'secondName': ?opt(input.secondName),
          'firstLastName': input.firstLastName.trim(),
          'secondLastName': ?opt(input.secondLastName),
        },
      }),
    );
    _ensureSuccess(json, fallback: 'No se pudieron guardar tus datos.');
    return fetchProfile();
  }

  /// Todas las respuestas de login traen la sesión en `tokenData`.
  Future<void> _startSession(
    AppUser user,
    Map<String, dynamic> json, {
    required String fallback,
  }) async {
    final tokens = json['tokenData'] as Map<String, dynamic>? ?? const {};
    final access = _nonEmpty(tokens['accessToken']);
    final refresh = _nonEmpty(tokens['refreshToken']);
    if (access == null || refresh == null) throw AuthException(fallback);
    await _session.start(
      user: user,
      accessToken: access,
      refreshToken: refresh,
      expiresIn: (tokens['expiresIn'] as num?)?.toInt() ?? 0,
    );
  }

  /// Mensaje único para cualquier falla del flujo de Google (SDK, API o red).
  static const googleErrorMessage =
      'Error al utilizar Google. Por favor, intenta de nuevo más tarde o '
      'utiliza otra opción de inicio de sesión o de registro.';

  @override
  Future<AppUser?> signInWithGoogle() async {
    try {
      return await _signInWithGoogle();
    } catch (_) {
      throw const AuthException(googleErrorMessage);
    }
  }

  Future<AppUser?> _signInWithGoogle() async {
    final idToken = await _google.getIdToken();
    if (idToken == null) return null;

    final json = await _call(
      () => _api.post('/api/GoogleAuth/signin-google', {
        'typeOperation': 'A',
        'googleData': {'idToken': idToken},
      }, authenticated: false),
    );
    _ensureSuccess(json, fallback: googleErrorMessage);

    final data = json['userData'] as Map<String, dynamic>? ?? const {};
    // La API manda nombre y apellido por separado; si faltan, se parte el
    // nombre completo.
    final (first, last) = splitFullName(data['name']?.toString() ?? '');
    final user = AppUser(
      id: data['userId']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      firstName: _nonEmpty(data['given_name']) ?? first,
      firstLastName: _nonEmpty(data['family_name']) ?? last,
      role: UserRole.parent,
    );
    await _startSession(user, json, fallback: googleErrorMessage);
    return user;
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _pending.sendPasswordReset(email);

  @override
  Future<AppUser?> restoreSession() => _session.restore();

  @override
  Future<void> signOut() async {
    await _session.end();
    await _google.signOut();
    await _pending.signOut();
  }

  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// La API puede responder 200 con un responseCode distinto de "00"
  /// (p. ej. validaciones de la base de datos).
  void _ensureSuccess(Map<String, dynamic> json, {required String fallback}) {
    final code = json['responseCode']?.toString();
    if (code == null || code == '00') return;
    final message = json['responseMessage']?.toString() ?? '';
    throw AuthException(
      message.isEmpty ? fallback : ApiClient.translate(message),
    );
  }

  /// Google da el nombre completo; se toma la primera palabra como nombre
  /// y el resto como apellido.
  static (String, String) splitFullName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.first.isEmpty) return ('', '');
    return (parts.first, parts.skip(1).join(' '));
  }
}
