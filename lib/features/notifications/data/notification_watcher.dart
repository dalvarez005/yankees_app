import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/notifications/local_notifier.dart';
import 'notification_repository.dart';

/// Recuerda, por usuario, hasta qué notificación ya se avisó en este
/// teléfono (para no repetir avisos entre aperturas de la app).
abstract class NotifiedMarkStore {
  Future<DateTime?> read(String userId);
  Future<void> write(String userId, DateTime mark);
}

class SecureNotifiedMarkStore implements NotifiedMarkStore {
  SecureNotifiedMarkStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String userId) => 'notified_until_$userId';

  @override
  Future<DateTime?> read(String userId) async {
    final raw = await _storage.read(key: _key(userId));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  @override
  Future<void> write(String userId, DateTime mark) =>
      _storage.write(key: _key(userId), value: mark.toUtc().toIso8601String());
}

class MemoryNotifiedMarkStore implements NotifiedMarkStore {
  final _marks = <String, DateTime>{};

  @override
  Future<DateTime?> read(String userId) async => _marks[userId];

  @override
  Future<void> write(String userId, DateTime mark) async =>
      _marks[userId] = mark;
}

/// Vigila las notificaciones del usuario y muestra las nuevas como
/// notificaciones del sistema.
///
/// Funciona mientras la app está abierta o en segundo plano reciente: la
/// consulta la hace la propia app. Para avisar con la app cerrada hace
/// falta push del servidor (FCM), que usaría este mismo [LocalNotifier].
class NotificationWatcher {
  NotificationWatcher({
    this._repository,
    this._notifier,
    NotifiedMarkStore? store,
    this.interval = const Duration(seconds: 30),
    this.maxPerCheck = 4,
  }) : _store = store ?? SecureNotifiedMarkStore();

  final NotificationRepository? _repository;
  final LocalNotifier? _notifier;
  final NotifiedMarkStore _store;

  /// Cada cuánto se consulta a la API.
  final Duration interval;

  /// Más de estas en una sola consulta se resumen en un solo aviso.
  final int maxPerCheck;

  NotificationRepository get _repo =>
      _repository ?? NotificationRepository.instance;
  LocalNotifier get _local => _notifier ?? LocalNotifier.instance;

  /// Cambia cada vez que llegan notificaciones nuevas, para que la campana
  /// de la app actualice su contador sin esperar a que se abra la lista.
  static final arrivals = ValueNotifier<int>(0);

  Timer? _timer;
  String? _userId;
  bool _checking = false;
  bool _push = false;

  bool get running => _userId != null;

  /// Los avisos llegan por push: el sistema ya los muestra con la app en
  /// segundo plano o cerrada.
  bool get pushActive => _push;

  /// Empieza a vigilar para [userId].
  ///
  /// Sin [push] consulta ya y luego cada [interval]. Con [push] no hay
  /// temporizador: solo se pone al día (sin volver a avisar de lo que el
  /// sistema ya mostró) y muestra los que lleguen con la app abierta.
  Future<void> start(String userId, {bool push = false}) async {
    stop();
    _userId = userId;
    _push = push;
    await check(silent: push);
    if (_userId == userId && !push) {
      _timer = Timer.periodic(interval, (_) => check());
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _userId = null;
    _push = false;
  }

  /// Consulta ahora. Devuelve cuántas notificaciones nuevas encontró.
  ///
  /// Con [silent] no las muestra (ya las mostró el sistema por push): solo
  /// avanza el punto de partida y refresca el contador de la campana.
  Future<int> check({bool silent = false}) async {
    final userId = _userId;
    if (userId == null || _checking) return 0;
    _checking = true;
    try {
      final mark = await _store.read(userId);
      if (mark == null) {
        // Primera vez en este teléfono: lo que ya existe no se avisa; se
        // toma como punto de partida.
        final page = await _repo.myNotifications();
        await _store.write(userId, _latest(page.items) ?? _epoch);
        return 0;
      }

      final page = await _repo.myNotifications(unreadOnly: true);
      if (_userId != userId) return 0; // Cambió la sesión mientras tanto.
      final fresh = [
        for (final n in page.items)
          if (n.createdAt.isAfter(mark)) n,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (fresh.isEmpty) return 0;

      if (silent) {
        // Nada que mostrar: el push ya avisó.
      } else if (fresh.length > maxPerCheck) {
        await _local.show(
          id: _summaryId,
          title: 'Club Yankees',
          body: 'Tienes ${fresh.length} notificaciones nuevas.',
        );
      } else {
        for (final n in fresh) {
          await _local.show(
            id: n.id.hashCode & 0x7fffffff,
            title: n.title.isEmpty ? 'Club Yankees' : n.title,
            body: n.body,
            payload: n.id,
          );
        }
      }
      await _store.write(userId, _latest(fresh)!);
      arrivals.value++;
      return fresh.length;
    } on NotificationException {
      return 0; // Sin conexión: se reintenta en la próxima vuelta.
    } finally {
      _checking = false;
    }
  }

  static const _summaryId = 1;
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static DateTime? _latest(List<AppNotification> items) => items.isEmpty
      ? null
      : items.map((n) => n.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
}
