import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones del sistema (banner, sonido y bandeja del teléfono).
///
/// Por defecto no hace nada (pruebas y plataformas sin soporte); `main`
/// instala [DeviceLocalNotifier].
abstract class LocalNotifier {
  static LocalNotifier instance = const NoopLocalNotifier();

  /// false: no hay notificaciones del sistema (no vale la pena vigilar).
  bool get available;

  /// Prepara el plugin. [onTap] recibe el `payload` de la notificación que
  /// el usuario tocó.
  Future<void> init({required void Function(String? payload) onTap});

  /// Pide el permiso al usuario (el sistema solo pregunta la primera vez).
  /// Devuelve si quedó concedido.
  Future<bool> requestPermission();

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// Quita las notificaciones de la bandeja (al cerrar sesión).
  Future<void> clear();
}

class NoopLocalNotifier implements LocalNotifier {
  const NoopLocalNotifier();

  @override
  bool get available => false;
  @override
  Future<void> init({required void Function(String? payload) onTap}) async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {}
  @override
  Future<void> clear() async {}
}

/// Implementación real sobre `flutter_local_notifications`.
class DeviceLocalNotifier implements LocalNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  void Function(String? payload)? _onTap;

  static const _channel = AndroidNotificationDetails(
    'club_avisos',
    'Avisos del club',
    channelDescription: 'Pagos, comprobantes y validaciones de tu cuenta.',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
  );

  @override
  bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> init({required void Function(String? payload) onTap}) async {
    _onTap = onTap;
    if (_ready || !available) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        // El permiso se pide después, con requestPermission().
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => _onTap?.call(r.payload),
    );
    // El canal tiene que existir antes de que llegue un push: el servidor
    // manda las notificaciones a "club_avisos".
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'club_avisos',
            'Avisos del club',
            description: 'Pagos, comprobantes y validaciones de tu cuenta.',
            importance: Importance.high,
          ),
        );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!available) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> clear() async {
    if (_ready) await _plugin.cancelAll();
  }
}
