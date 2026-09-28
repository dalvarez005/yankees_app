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
          // La API exige todos los campos string; vacío = no aplica.
          'secondName': '',
          'secondLastName': '',
        },
      }, authenticated: false),
    );
    _ensureSuccess(json, fallback: 'No se pudo crear la cuenta.');

    // El registro no abre sesión: se entra con las mismas credenciales.
    // Si ese paso falla la cuenta igual quedó creada; se sigue sin sesión
    // y el usuario podrá entrar desde el login.
    try {
      return await _passwordLogin(
        normalizedEmail,
        password,
        firstName: firstName.trim(),
        firstLastName: firstLastName.trim(),
      );
    } on AuthException {
      final data = json['userData'] as Map<String, dynamic>? ?? const {};
      return AppUser(
        id: data['userId']?.toString() ?? '',
        email: normalizedEmail,
        firstName: firstName.trim(),
        firstLastName: firstLastName.trim(),
        role: UserRole.parent,
      );
    }
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) =>
      _passwordLogin(email.trim().toLowerCase(), password);

  /// La API solo devuelve userId y tokens (no el nombre): si no se conoce,
  /// la app muestra el correo hasta que exista un endpoint de perfil.
  Future<AppUser> _passwordLogin(
    String email,
    String password, {
    String firstName = '',
    String firstLastName = '',
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

    final user = AppUser(
      id: json['userId']?.toString() ?? '',
      email: email,
      firstName: firstName,
      firstLastName: firstLastName,
      role: UserRole.parent,
    );
    await _startSession(
      user,
      accessToken: json['sessionToken'],
      refreshToken: json['refreshToken'],
      expiresIn: json['expiresIn'],
      fallback: 'No se pudo iniciar sesión.',
    );
    return user;
  }

  Future<void> _startSession(
    AppUser user, {
    required Object? accessToken,
    required Object? refreshToken,
    required Object? expiresIn,
    required String fallback,
  }) async {
    final access = _nonEmpty(accessToken);
    final refresh = _nonEmpty(refreshToken);
    if (access == null || refresh == null) throw AuthException(fallback);
    await _session.start(
      user: user,
      accessToken: access,
      refreshToken: refresh,
      expiresIn: (expiresIn as num?)?.toInt() ?? 0,
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
        'googleData': {
          'idToken': idToken,
          // No se usan en esta operación, pero la API los exige.
          'code': '',
          'accessToken': '',
          'refreshToken': '',
        },
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
    // Google devuelve la sesión dentro de tokenData (formato OAuth).
    final tokens =
        (json['tokenData'] ?? json['TokenData']) as Map<String, dynamic>? ??
        const {};
    await _startSession(
      user,
      accessToken: tokens['access_token'],
      refreshToken: tokens['refresh_token'],
      expiresIn: tokens['expires_in'],
      fallback: googleErrorMessage,
    );
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
