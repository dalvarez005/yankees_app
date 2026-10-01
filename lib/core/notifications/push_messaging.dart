import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push del servidor (Firebase Cloud Messaging): identifica este teléfono
/// con un token y avisa cuando llega o se toca un push.
///
/// Por defecto no hace nada (pruebas y plataformas sin Firebase); `main`
/// instala [FirebasePushMessaging] si Firebase pudo iniciarse.
abstract class PushMessaging {
  static PushMessaging instance = const NoopPushMessaging();

  /// false: no hay push; la app consulta las notificaciones por su cuenta.
  bool get available;

  /// "android" o "ios".
  String get platform;

  /// Token de FCM de esta instalación, o null si no se pudo obtener.
  Future<String?> token();

  /// El token cambió (reinstalación, restauración, rotación de Firebase).
  Stream<String> get onTokenRefresh;

  /// Llegó un push con la app en primer plano (el sistema no lo muestra).
  Stream<void> get onForegroundMessage;

  /// El usuario tocó un push con la app en segundo plano.
  Stream<void> get onOpened;

  /// La app se abrió desde cero al tocar un push.
  Future<bool> openedFromPush();
}

class NoopPushMessaging implements PushMessaging {
  const NoopPushMessaging();

  @override
  bool get available => false;
  @override
  String get platform => 'android';
  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<void> get onForegroundMessage => const Stream.empty();
  @override
  Stream<void> get onOpened => const Stream.empty();
  @override
  Future<bool> openedFromPush() async => false;
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging._();

  /// Inicia Firebase. Devuelve null si esta plataforma no tiene
  /// configuración (p. ej. iOS sin GoogleService-Info.plist o escritorio):
  /// la app sigue funcionando sin push.
  static Future<FirebasePushMessaging?> create() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }
    try {
      await Firebase.initializeApp();
      return FirebasePushMessaging._();
    } catch (e) {
      debugPrint('Push no disponible: $e');
      return null;
    }
  }

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  @override
  bool get available => true;

  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<String?> token() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS && !await _apnsReady()) {
        return null;
      }
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('No se pudo obtener el token de push: $e');
      return null;
    }
  }

  /// En iOS el token de FCM solo existe cuando Apple ya entregó el suyo
  /// (APNs), y eso tarda un momento tras conceder el permiso. En simulador
  /// o sin la capacidad de push nunca llega.
  Future<bool> _apnsReady() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      if (await _fcm.getAPNSToken() != null) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    debugPrint('Push no disponible: Apple no entregó el token de APNs');
    return false;
  }

  @override
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  @override
  Stream<void> get onForegroundMessage => FirebaseMessaging.onMessage;

  @override
  Stream<void> get onOpened => FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<bool> openedFromPush() async => await _fcm.getInitialMessage() != null;
}
