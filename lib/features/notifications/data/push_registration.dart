import 'dart:async';

import '../../../core/notifications/push_messaging.dart';
import 'notification_repository.dart';

/// Registra este teléfono en la API para recibir push mientras haya sesión,
/// y lo quita al cerrarla.
class PushRegistration {
  PushRegistration({PushMessaging? push, NotificationRepository? repository})
    : _pushOverride = push,
      _repositoryOverride = repository;

  static PushRegistration instance = PushRegistration();

  final PushMessaging? _pushOverride;
  final NotificationRepository? _repositoryOverride;

  PushMessaging get _push => _pushOverride ?? PushMessaging.instance;
  NotificationRepository get _repository =>
      _repositoryOverride ?? NotificationRepository.instance;

  String? _token;
  StreamSubscription<String>? _refresh;

  /// Hay un teléfono registrado: los avisos llegan por push.
  bool get active => _token != null;

  /// Devuelve true si el teléfono quedó registrado. Con false (sin Firebase,
  /// sin token o sin conexión) la app consulta las notificaciones ella misma.
  Future<bool> register() async {
    final push = _push;
    if (!push.available) return false;
    final token = await push.token();
    if (token == null || token.isEmpty) return false;
    try {
      await _repository.registerDevice(token, push.platform);
    } on NotificationException {
      return false;
    }
    _token = token;
    await _refresh?.cancel();
    // Firebase puede rotar el token: se vuelve a registrar el nuevo.
    _refresh = push.onTokenRefresh.listen((fresh) async {
      try {
        await _repository.registerDevice(fresh, push.platform);
        _token = fresh;
      } on NotificationException {
        // Se reintenta en el próximo inicio de sesión.
      }
    });
    return true;
  }

  /// Al cerrar la sesión: este teléfono deja de recibir los avisos de la
  /// cuenta. [accessToken] es el de la sesión que se cierra, para poder
  /// avisar a la API aunque la sesión local ya se haya borrado.
  Future<void> unregister({String? accessToken}) async {
    await _refresh?.cancel();
    _refresh = null;
    final token = _token;
    _token = null;
    if (token == null) return;
    try {
      await _repository.unregisterDevice(token, accessToken: accessToken);
    } on NotificationException {
      // Sin conexión: la API lo reasigna cuando otra cuenta entre aquí.
    }
  }
}
