import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../auth/data/app_user.dart';

/// Recuerda qué usuarios ya confirmaron sus datos en este dispositivo.
///
/// La API aún no guarda si el perfil fue revisado; cuando lo haga, esto
/// debería leerse de ahí para no volver a pedirlo en otro teléfono.
abstract class ProfileReviewStore {
  static ProfileReviewStore instance = SecureProfileReviewStore();

  Future<bool> isReviewed(String userId);
  Future<void> markReviewed(String userId);

  /// Hay que pedir confirmación si nunca la hizo en este dispositivo o si
  /// los datos son de relleno (Google sin apellido, nombre = correo).
  Future<bool> needsReview(AppUser user) async =>
      hasPlaceholderData(user) || !await isReviewed(user.id);

  static bool hasPlaceholderData(AppUser user) =>
      user.firstName.trim().isEmpty ||
      user.firstLastName.trim().isEmpty ||
      isPlaceholder(user.firstName, user) ||
      isPlaceholder(user.firstLastName, user);

  /// Valores que la API pone cuando Google no manda el dato: el correo como
  /// nombre y "GOOGLE" como apellido. No sirven como nombre real.
  static bool isPlaceholder(String? value, AppUser user) {
    final v = value?.trim().toLowerCase() ?? '';
    return v == 'google' || v == user.email.toLowerCase() || v.contains('@');
  }
}

class SecureProfileReviewStore extends ProfileReviewStore {
  SecureProfileReviewStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'yankees.profileReviewed';

  Future<Set<String>> _read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return {};
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<bool> isReviewed(String userId) async =>
      (await _read()).contains(userId);

  @override
  Future<void> markReviewed(String userId) async {
    final ids = await _read()
      ..add(userId);
    await _storage.write(key: _key, value: jsonEncode(ids.toList()));
  }
}

class MemoryProfileReviewStore extends ProfileReviewStore {
  final reviewed = <String>{};

  @override
  Future<bool> isReviewed(String userId) async => reviewed.contains(userId);

  @override
  Future<void> markReviewed(String userId) async => reviewed.add(userId);
}
