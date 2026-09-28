import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/data/app_user.dart';

/// Sesión emitida por la API: token de acceso corto + refresh token para
/// renovarlo sin volver a pedir credenciales.
class StoredSession {
  const StoredSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;

  /// La API lo rota en cada renovación: siempre hay que guardar el último.
  final String refreshToken;
  final DateTime expiresAt;
  final AppUser user;

  /// Vence dentro de [margin] (se renueva un poco antes para no fallar).
  bool expiresWithin(Duration margin, {DateTime? now}) =>
      (now ?? DateTime.now()).add(margin).isAfter(expiresAt);

  StoredSession copyWith({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
  }) => StoredSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    user: user,
  );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'user': user.toJson(),
  };

  factory StoredSession.fromJson(Map<String, dynamic> json) => StoredSession(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
  );
}

abstract class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// Guarda la sesión en Keychain (iOS) / Keystore (Android).
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'yankees.session';

  @override
  Future<StoredSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      // Dato corrupto o ilegible (p. ej. tras reinstalar): se descarta.
      if (kDebugMode) debugPrint('Sesión guardada ilegible, se descarta: $e');
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Para pruebas y para el modo mock.
class MemorySessionStore implements SessionStore {
  StoredSession? session;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}
