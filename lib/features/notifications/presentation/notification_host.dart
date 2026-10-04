import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/notifications/local_notifier.dart';
import '../../auth/data/app_user.dart';
import '../../../core/notifications/push_messaging.dart';
import '../data/notification_watcher.dart';
import '../data/push_registration.dart';
import 'notifications_page.dart';
import 'standalone.dart' if (dart.library.js_interop) 'standalone_web.dart';

/// Envuelve el inicio del usuario con sesión: al entrar pide el permiso de
/// notificaciones y, mientras esté en pantalla, avisa con notificaciones del
/// sistema de lo nuevo que llega. Tocar una abre la lista de notificaciones.
/// Web: el navegador solo deja pedir el permiso de notificaciones con un
/// toque. Mientras haga falta, el inicio muestra `WebPushPrompt`.
abstract final class WebPush {
  /// Hay push en este navegador y todavía no se dio permiso.
  static final offer = ValueNotifier<bool>(false);

  /// iPhone/iPad en Safari sin agregar a inicio: ahí no hay push.
  static final needsInstall = ValueNotifier<bool>(false);

  static _NotificationHostState? _host;

  /// Pide el permiso (desde el botón) y, si lo dan, registra el navegador.
  static Future<bool> enable() async {
    final granted = await PushMessaging.instance.requestPermission();
    if (granted) {
      offer.value = false;
      await _host?._startPush();
    }
    return granted;
  }
}

class NotificationHost extends StatefulWidget {
  const NotificationHost({
    super.key,
    required this.user,
    required this.child,
    this.watcher,
    this.registration,
  });

  final AppUser user;
  final Widget child;

  /// Para pruebas; por defecto uno propio.
  final NotificationWatcher? watcher;

  /// Para pruebas; por defecto [PushRegistration.instance].
  final PushRegistration? registration;

  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost>
    with WidgetsBindingObserver {
  late final _watcher = widget.watcher ?? NotificationWatcher();
  late final _registration = widget.registration ?? PushRegistration.instance;
  final _subscriptions = <StreamSubscription<void>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_setUp());
  }

  Future<void> _setUp() async {
    if (kIsWeb) return _setUpWeb();
    final notifier = LocalNotifier.instance;
    if (!notifier.available) return;
    await notifier.init(onTap: _onTap);
    // El sistema solo muestra el diálogo la primera vez; si ya se decidió,
    // esto solo devuelve el estado actual.
    final granted = await notifier.requestPermission();
    if (!mounted || !granted) return;

    // Con push (Firebase) los avisos llegan aunque la app esté cerrada; sin
    // él, la app los consulta cada cierto tiempo mientras esté abierta.
    final push = await _registration.register();
    if (!mounted) return;
    if (push) {
      final messaging = PushMessaging.instance;
      _subscriptions
        // En primer plano el sistema no muestra el push: lo muestra la app.
        ..add(messaging.onForegroundMessage.listen((_) => _watcher.check()))
        ..add(messaging.onOpened.listen((_) => _onTap(null)));
      if (await messaging.openedFromPush()) _onTap(null);
      if (!mounted) return;
    }
    await _watcher.start(widget.user.id, push: push);
  }

  /// Web: sin notificaciones locales. Con permiso, push; sin él, se ofrece
  /// activarlo y mientras tanto la campana se actualiza consultando.
  Future<void> _setUpWeb() async {
    WebPush._host = this;
    final messaging = PushMessaging.instance;
    if (!messaging.available) {
      WebPush.needsInstall.value =
          defaultTargetPlatform == TargetPlatform.iOS && !_isStandalone();
      await _watcher.start(widget.user.id);
      return;
    }
    if (await messaging.permissionGranted) {
      await _startPush();
    } else {
      WebPush.offer.value = true;
      await _watcher.start(widget.user.id);
    }
  }

  /// Registra este dispositivo para push y deja de consultar.
  Future<void> _startPush() async {
    if (!mounted) return;
    final push = await _registration.register();
    if (!mounted) return;
    if (push) {
      final messaging = PushMessaging.instance;
      _subscriptions
        ..add(messaging.onForegroundMessage.listen((_) => _watcher.check()))
        ..add(messaging.onOpened.listen((_) => _onTap(null)));
    }
    await _watcher.start(widget.user.id, push: push);
  }

  static bool _isStandalone() => isStandaloneWebApp();

  void _onTap(String? payload) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsPage(user: widget.user),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app se consulta enseguida, sin esperar al temporizador.
    if (state == AppLifecycleState.resumed && _watcher.running) {
      unawaited(_watcher.check(silent: _watcher.pushActive));
    }
  }

  @override
  void dispose() {
    if (WebPush._host == this) WebPush._host = null;
    WebPush.offer.value = false;
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _watcher.stop();
    // Al salir de la sesión no deben quedar avisos de esta cuenta.
    unawaited(LocalNotifier.instance.clear());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
