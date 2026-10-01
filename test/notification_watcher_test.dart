import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yankees/core/notifications/local_notifier.dart';
import 'package:yankees/core/notifications/push_messaging.dart';
import 'package:yankees/features/auth/data/app_user.dart';
import 'package:yankees/features/notifications/data/notification_repository.dart';
import 'package:yankees/features/notifications/data/notification_watcher.dart';
import 'package:yankees/features/notifications/data/push_registration.dart';
import 'package:yankees/features/notifications/presentation/notification_host.dart';

/// Registra lo que se mostraría en el teléfono.
class _FakeNotifier implements LocalNotifier {
  _FakeNotifier({this.grant = true});

  final bool grant;
  final shown = <({int id, String title, String body, String? payload})>[];
  var permissionRequests = 0;
  var cleared = 0;
  void Function(String? payload)? onTap;

  @override
  bool get available => true;

  @override
  Future<void> init({required void Function(String? payload) onTap}) async {
    this.onTap = onTap;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    shown.add((id: id, title: title, body: body, payload: payload));
  }

  @override
  Future<void> clear() async => cleared++;
}

/// Notificaciones que se pueden ir agregando durante la prueba.
class _FakeRepo implements NotificationRepository {
  final items = <AppNotification>[];
  var fail = false;
  var calls = 0;

  void add(
    String id,
    DateTime at, {
    String title = 'Aviso',
    bool read = false,
  }) {
    items.add(
      AppNotification(
        id: id,
        type: NotificationTypes.voucherSubmitted,
        title: title,
        body: 'Cuerpo de $id',
        createdAt: at,
        readAt: read ? at : null,
      ),
    );
  }

  @override
  Future<NotificationPage> myNotifications({
    int page = 1,
    bool unreadOnly = false,
  }) async {
    calls++;
    if (fail) throw const NotificationException('sin conexión');
    final list = [
      for (final n in items)
        if (!unreadOnly || n.unread) n,
    ];
    return NotificationPage(
      items: list,
      unreadCount: items.where((n) => n.unread).length,
    );
  }

  @override
  Future<int> markAsRead({List<String>? ids, bool all = false}) async => 0;

  final devices = <String, String>{};
  var failRegister = false;

  @override
  Future<void> registerDevice(String token, String platform) async {
    if (failRegister) throw const NotificationException('sin conexión');
    devices[token] = platform;
  }

  @override
  Future<void> unregisterDevice(String token) async => devices.remove(token);
}

/// Push controlable desde la prueba.
class _FakePush implements PushMessaging {
  _FakePush({this.currentToken = 'tok-1', this.available = true});

  String? currentToken;
  @override
  final bool available;
  var launchedFromPush = false;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<void>.broadcast();
  final opened = StreamController<void>.broadcast();

  @override
  String get platform => 'android';
  @override
  Future<String?> token() async => currentToken;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<void> get onForegroundMessage => foreground.stream;
  @override
  Stream<void> get onOpened => opened.stream;
  @override
  Future<bool> openedFromPush() async => launchedFromPush;
}

void main() {
  final t0 = DateTime.utc(2026, 9, 30, 10);
  late _FakeRepo repo;
  late _FakeNotifier notifier;
  late MemoryNotifiedMarkStore store;

  NotificationWatcher watcher({int maxPerCheck = 4}) => NotificationWatcher(
    repository: repo,
    notifier: notifier,
    store: store,
    // Sin temporizador real en las pruebas: se llama a check() a mano.
    interval: const Duration(days: 1),
    maxPerCheck: maxPerCheck,
  );

  setUp(() {
    repo = _FakeRepo();
    notifier = _FakeNotifier();
    store = MemoryNotifiedMarkStore();
  });

  group('NotificationWatcher', () {
    test('la primera vez no avisa de lo que ya existía', () async {
      repo.add('viejo', t0);
      final w = watcher();
      await w.start('u1');
      expect(notifier.shown, isEmpty);
      w.stop();
    });

    test('avisa de lo nuevo, una sola vez', () async {
      repo.add('viejo', t0);
      final w = watcher();
      await w.start('u1');

      repo.add(
        'n1',
        t0.add(const Duration(minutes: 1)),
        title: 'Pago aprobado',
      );
      expect(await w.check(), 1);
      expect(notifier.shown.single.title, 'Pago aprobado');
      expect(notifier.shown.single.body, 'Cuerpo de n1');
      expect(notifier.shown.single.payload, 'n1');

      // En la siguiente consulta ya no se repite.
      expect(await w.check(), 0);
      expect(notifier.shown, hasLength(1));
      w.stop();
    });

    test('no avisa de las que ya están leídas', () async {
      final w = watcher();
      await w.start('u1');
      repo.add('leida', t0.add(const Duration(minutes: 1)), read: true);
      expect(await w.check(), 0);
      expect(notifier.shown, isEmpty);
      w.stop();
    });

    test('muchas a la vez se resumen en un solo aviso', () async {
      final w = watcher(maxPerCheck: 3);
      await w.start('u1');
      for (var i = 1; i <= 5; i++) {
        repo.add('n$i', t0.add(Duration(minutes: i)));
      }
      expect(await w.check(), 5);
      expect(notifier.shown.single.body, 'Tienes 5 notificaciones nuevas.');
      w.stop();
    });

    test('recuerda hasta dónde avisó aunque se reinicie la app', () async {
      final first = watcher();
      await first.start('u1');
      repo.add('n1', t0.add(const Duration(minutes: 1)));
      await first.check();
      first.stop();

      // "Se cerró y volvió a abrir": mismo teléfono, nuevo vigía.
      final second = watcher();
      await second.start('u1');
      expect(notifier.shown, hasLength(1));

      // Lo que llegó mientras estaba cerrada sí se avisa al volver.
      repo.add('n2', t0.add(const Duration(minutes: 2)));
      expect(await second.check(), 1);
      expect(notifier.shown.last.payload, 'n2');
      second.stop();
    });

    test('cada usuario tiene su propio punto de partida', () async {
      final w = watcher();
      await w.start('u1');
      repo.add('n1', t0.add(const Duration(minutes: 1)));
      await w.check();
      expect(notifier.shown, hasLength(1));

      // Otra cuenta en el mismo teléfono: lo existente no se le avisa.
      await w.start('u2');
      expect(notifier.shown, hasLength(1));
      w.stop();
    });

    test('sin conexión no avisa ni rompe; al volver, avisa', () async {
      final w = watcher();
      await w.start('u1');
      repo.add('n1', t0.add(const Duration(minutes: 1)));
      repo.fail = true;
      expect(await w.check(), 0);
      repo.fail = false;
      expect(await w.check(), 1);
      w.stop();
    });

    test('con push: se pone al día sin volver a avisar', () async {
      final w = watcher();
      await w.start('u1'); // primera vez: punto de partida
      w.stop();

      // Llegó con la app cerrada: el sistema ya mostró el push.
      repo.add('n1', t0.add(const Duration(minutes: 1)));
      await w.start('u1', push: true);
      expect(notifier.shown, isEmpty);
      expect(w.pushActive, isTrue);

      // Y tampoco se repite después.
      expect(await w.check(), 0);
      expect(notifier.shown, isEmpty);
      w.stop();
    });

    test('con push: lo que llega con la app abierta sí se muestra', () async {
      final w = watcher();
      await w.start('u1', push: true);
      repo.add(
        'n1',
        t0.add(const Duration(minutes: 1)),
        title: 'Pago aprobado',
      );
      // La app recibe el push en primer plano y consulta.
      expect(await w.check(), 1);
      expect(notifier.shown.single.title, 'Pago aprobado');
      w.stop();
    });

    test('ponerse al día actualiza la campana', () async {
      final w = watcher();
      await w.start('u1', push: true);
      final before = NotificationWatcher.arrivals.value;
      repo.add('n1', t0.add(const Duration(minutes: 1)));
      await w.check(silent: true);
      expect(NotificationWatcher.arrivals.value, before + 1);
      w.stop();
    });

    test('detenido no consulta', () async {
      final w = watcher();
      await w.start('u1');
      w.stop();
      final before = repo.calls;
      expect(await w.check(), 0);
      expect(repo.calls, before);
      expect(w.running, isFalse);
    });
  });

  group('PushRegistration', () {
    test('registra el token del teléfono y lo quita al salir', () async {
      final push = _FakePush();
      final reg = PushRegistration(push: push, repository: repo);
      expect(await reg.register(), isTrue);
      expect(repo.devices, {'tok-1': 'android'});
      expect(reg.active, isTrue);

      await reg.unregister();
      expect(repo.devices, isEmpty);
      expect(reg.active, isFalse);
    });

    test('si Firebase rota el token, registra el nuevo', () async {
      final push = _FakePush();
      final reg = PushRegistration(push: push, repository: repo);
      await reg.register();
      push.refresh.add('tok-2');
      await Future<void>.delayed(Duration.zero);
      expect(repo.devices.keys, contains('tok-2'));

      await reg.unregister();
      expect(repo.devices.keys, isNot(contains('tok-2')));
    });

    test('sin Firebase, sin token o sin conexión no hay push', () async {
      expect(
        await PushRegistration(
          push: _FakePush(available: false),
          repository: repo,
        ).register(),
        isFalse,
      );
      expect(
        await PushRegistration(
          push: _FakePush(currentToken: null),
          repository: repo,
        ).register(),
        isFalse,
      );
      repo.failRegister = true;
      expect(
        await PushRegistration(push: _FakePush(), repository: repo).register(),
        isFalse,
      );
      expect(repo.devices, isEmpty);
    });
  });

  group('NotificationHost con push', () {
    const user = AppUser(
      id: 'u1',
      email: 'ana@test.com',
      firstName: 'Ana',
      firstLastName: 'Gómez',
    );

    Future<(NotificationWatcher, _FakePush)> pump(WidgetTester tester) async {
      final w = watcher();
      final push = _FakePush();
      LocalNotifier.instance = notifier;
      PushMessaging.instance = push;
      addTearDown(() {
        LocalNotifier.instance = const NoopLocalNotifier();
        PushMessaging.instance = const NoopPushMessaging();
      });
      NotificationRepository.instance = repo;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationHost(
            user: user,
            watcher: w,
            registration: PushRegistration(push: push, repository: repo),
            child: const Scaffold(body: Text('inicio')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (w, push);
    }

    testWidgets('registra el teléfono y vigila en modo push', (tester) async {
      final (w, _) = await pump(tester);
      expect(repo.devices, {'tok-1': 'android'});
      expect(w.running, isTrue);
      expect(w.pushActive, isTrue);
    });

    testWidgets('un push en primer plano se muestra como aviso', (
      tester,
    ) async {
      final (_, push) = await pump(tester);
      repo.add(
        'n1',
        t0.add(const Duration(minutes: 1)),
        title: 'Pago aprobado',
      );
      push.foreground.add(null);
      await tester.pumpAndSettle();
      expect(notifier.shown.single.title, 'Pago aprobado');
    });

    testWidgets('tocar un push abre la lista', (tester) async {
      final (_, push) = await pump(tester);
      push.opened.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Notificaciones'), findsOneWidget);
    });
  });

  group('NotificationHost', () {
    const user = AppUser(
      id: 'u1',
      email: 'ana@test.com',
      firstName: 'Ana',
      firstLastName: 'Gómez',
    );

    Future<NotificationWatcher> pump(WidgetTester tester) async {
      final w = watcher();
      LocalNotifier.instance = notifier;
      addTearDown(() => LocalNotifier.instance = const NoopLocalNotifier());
      NotificationRepository.instance = repo;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationHost(
            user: user,
            watcher: w,
            child: const Scaffold(body: Text('inicio')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return w;
    }

    testWidgets('al entrar pide el permiso y empieza a vigilar', (
      tester,
    ) async {
      final w = await pump(tester);
      expect(notifier.permissionRequests, 1);
      expect(w.running, isTrue);
      expect(find.text('inicio'), findsOneWidget);
    });

    testWidgets('sin permiso no vigila', (tester) async {
      notifier = _FakeNotifier(grant: false);
      final w = await pump(tester);
      expect(notifier.permissionRequests, 1);
      expect(w.running, isFalse);
    });

    testWidgets('tocar una notificación abre la lista', (tester) async {
      await pump(tester);
      notifier.onTap!('n1');
      await tester.pumpAndSettle();
      expect(find.text('Notificaciones'), findsOneWidget);
    });

    testWidgets('al salir deja de vigilar y limpia la bandeja', (tester) async {
      final w = await pump(tester);
      await tester.pumpWidget(const MaterialApp(home: Text('login')));
      await tester.pumpAndSettle();
      expect(w.running, isFalse);
      expect(notifier.cleared, 1);
    });

    testWidgets('al volver a la app consulta enseguida', (tester) async {
      await pump(tester);
      final before = repo.calls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repo.calls, greaterThan(before));
    });
  });
}
