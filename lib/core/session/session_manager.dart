import 'dart:async';

import '../../features/auth/data/app_user.dart';
import '../network/api_client.dart';
import 'session_store.dart';

/// Mantiene la sesión con la API: guarda los tokens, renueva el de acceso
/// con el refresh token (que la API rota en cada uso) y la cierra.
class SessionManager implements Authenticator {
  SessionManager({
    required ApiClient api,
    required SessionStore store,
    DateTime Function()? clock,
  }) : _api = api,
       _store = store,
       _now = clock ?? DateTime.now;

  // ignore_for_file: prefer_initializing_formals
  final ApiClient _api;
  final SessionStore _store;
  final DateTime Function() _now;

  StoredSession? _session;
  Future<String?>? _refreshing;

  /// Se renueva un poco antes de vencer para no mandar tokens al límite.
  static const refreshMargin = Duration(seconds: 30);

  /// Se llama cuando la API rechaza el refresh token (sesión revocada o
  /// vencida): la app debe volver al login.
  void Function()? onSessionExpired;

  AppUser? get currentUser => _session?.user;

  /// Token de acceso guardado, sin renovarlo.
  String? get currentAccessToken => _session?.accessToken;

  /// Arranca una sesión con la respuesta de login de la API.
  Future<void> start({
    required AppUser user,
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    _session = StoredSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: _now().add(Duration(seconds: expiresIn)),
      user: user,
    );
    await _store.write(_session!);
  }

  /// Actualiza los datos del usuario de la sesión (p. ej. tras pedir el
  /// perfil) sin tocar los tokens.
  Future<void> updateUser(AppUser user) async {
    final session = _session;
    if (session == null) return;
    _session = StoredSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      expiresAt: session.expiresAt,
      user: user,
    );
    await _store.write(_session!);
  }

  /// Al abrir la app: recupera la sesión guardada y la renueva si venció.
  /// Sin conexión se mantiene la sesión (se renovará en el próximo request).
  Future<AppUser?> restore() async {
    _session = await _store.read();
    if (_session == null) return null;
    if (_session!.expiresWithin(refreshMargin, now: _now())) {
      await _refresh(notifyExpired: false);
    }
    return _session?.user;
  }

  @override
  Future<String?> accessToken() async {
    final session = _session;
    if (session == null) return null;
    if (session.expiresWithin(refreshMargin, now: _now())) {
      return refreshAccessToken();
    }
    return session.accessToken;
  }

  /// Una sola renovación a la vez: si llegan varios requests juntos,
  /// todos esperan la misma (el refresh token solo sirve una vez).
  @override
  Future<String?> refreshAccessToken() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<String?> _refresh({bool notifyExpired = true}) async {
    final session = _session;
    if (session == null) return null;
    try {
      final json = await _api.post('/api/Session/refresh-token', {
        'refreshToken': session.refreshToken,
      }, authenticated: false);
      final tokens = json['tokenData'] as Map<String, dynamic>? ?? const {};
      final access = tokens['accessToken']?.toString();
      final refresh = tokens['refreshToken']?.toString();
      if (json['responseCode'] != '00' || access == null || refresh == null) {
        throw const ApiException('Respuesta inválida', statusCode: 401);
      }
      _session = session.copyWith(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: _now().add(
          Duration(seconds: (tokens['expiresIn'] as num?)?.toInt() ?? 0),
        ),
      );
      await _store.write(_session!);
      return access;
    } on ApiException catch (e) {
      // 401/05: refresh token inválido o revocado → la sesión terminó.
      // Otros errores (red, 5xx, 429) no cierran la sesión.
      if (e.statusCode == 401 || e.code == '05') {
        await _clear();
        if (notifyExpired) onSessionExpired?.call();
      }
      return null;
    }
  }

  /// Cierra la sesión en la API (si se puede) y borra todo localmente.
  /// Cierra la sesión en el teléfono al instante; el aviso a la API sigue
  /// en segundo plano para que la pantalla no espere a la red.
  Future<void> end() async {
    final session = _session;
    await _clear();
    if (session == null) return;
    unawaited(_logout(session.refreshToken));
  }

  Future<void> _logout(String refreshToken) async {
    try {
      await _api.post('/api/Session/logout', {
        'refreshToken': refreshToken,
      }, authenticated: false);
    } on ApiException {
      // Sin conexión igual se cierra localmente; el token vence solo.
    } catch (_) {}
  }

  Future<void> _clear() async {
    _session = null;
    await _store.clear();
  }
}
