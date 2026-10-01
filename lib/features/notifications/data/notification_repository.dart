import '../../../core/paging/page_of.dart';

import 'dart:convert';

import '../../../core/network/api_client.dart';

/// Tipos de notificación del contrato (§1.5).
abstract final class NotificationTypes {
  static const userPendingValidation = 'USER_PENDING_VALIDATION';
  static const userValidated = 'USER_VALIDATED';
  static const chargeCreated = 'CHARGE_CREATED';
  static const voucherSubmitted = 'VOUCHER_SUBMITTED';
  static const voucherApproved = 'VOUCHER_APPROVED';
  static const voucherRejected = 'VOUCHER_REJECTED';
  static const paymentReminder = 'PAYMENT_REMINDER';
}

/// Notificación in-app del usuario con sesión.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.data = const {},
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;

  /// `{userId}`, `{chargeId}`, `{voucherId, chargeId}`, `{overdueAmount}`…
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data,
    createdAt: createdAt,
    readAt: readAt ?? at,
  );

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final raw = j['data'];
    return AppNotification(
      id: j['notificationId']?.toString() ?? '',
      type: j['type']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      body: j['body']?.toString() ?? '',
      // Por si la API lo manda como texto JSON en vez de objeto.
      data: raw is Map<String, dynamic> ? raw : _decode(raw),
      createdAt:
          DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      readAt: DateTime.tryParse(j['readAt']?.toString() ?? ''),
    );
  }
}

Map<String, dynamic> _decode(Object? raw) {
  if (raw is! String || raw.isEmpty) return const {};
  try {
    final v = jsonDecode(raw);
    return v is Map<String, dynamic> ? v : const {};
  } on FormatException {
    return const {};
  }
}

class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.unreadCount,
    this.hasNext = false,
  });

  final List<AppNotification> items;
  final int unreadCount;
  final bool hasNext;
}

class NotificationException implements Exception {
  const NotificationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Notificaciones in-app (docs/API_PAGOS.md §3.7): cada usuario ve solo
/// las suyas.
abstract class NotificationRepository {
  /// Tamaño de página del contrato para notificaciones.
  static const pageSize = 30;

  static NotificationRepository instance = MockNotificationRepository();

  Future<NotificationPage> myNotifications({
    int page = 1,
    bool unreadOnly = false,
  });

  /// Marca las indicadas, o todas con [all]. Devuelve las no leídas.
  Future<int> markAsRead({List<String>? ids, bool all = false});

  /// Asocia este teléfono (token de FCM) al usuario con sesión para que la
  /// API le mande los push. [platform] es "android" o "ios".
  Future<void> registerDevice(String token, String platform);

  /// Deja de mandar push a este teléfono (al cerrar sesión).
  Future<void> unregisterDevice(String token);
}

class ApiNotificationRepository implements NotificationRepository {
  ApiNotificationRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/Notification';

  @override
  Future<NotificationPage> myNotifications({
    int page = 1,
    bool unreadOnly = false,
  }) async {
    final path = Uri(
      path: '$_base/GetMyNotifications',
      queryParameters: {
        'page': '$page',
        'pageSize': '${NotificationRepository.pageSize}',
        'unreadOnly': '$unreadOnly',
      },
    );
    final json = await _call(() => _api.get(path.toString()));
    return NotificationPage(
      items: [
        for (final n
            in (json['notificationData'] as List? ?? const [])
                .whereType<Map<String, dynamic>>())
          AppNotification.fromJson(n),
      ],
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      hasNext: json['hasNext'] == true,
    );
  }

  @override
  Future<int> markAsRead({List<String>? ids, bool all = false}) async {
    final json = await _call(
      () => _api.post('$_base/MarkAsRead', {
        if (all) 'all': true else 'notificationIds': ids ?? const <String>[],
      }),
    );
    return (json['unreadCount'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> registerDevice(String token, String platform) => _call(
    () => _api.post('$_base/RegisterDevice', {
      'token': token,
      'platform': platform,
    }),
  );

  @override
  Future<void> unregisterDevice(String token) =>
      _call(() => _api.post('$_base/UnregisterDevice', {'token': token}));

  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on ApiException catch (e) {
      throw NotificationException(e.message);
    }
  }
}

/// En memoria (modo sin API y pruebas).
class MockNotificationRepository implements NotificationRepository {
  MockNotificationRepository({
    this.latency = const Duration(milliseconds: 300),
    List<AppNotification>? seed,
  }) : _items = seed ?? _defaults();

  final Duration latency;
  final List<AppNotification> _items;

  static List<AppNotification> _defaults() {
    final now = DateTime.now();
    return [
      AppNotification(
        id: 'n1',
        type: NotificationTypes.voucherSubmitted,
        title: 'Nuevo comprobante',
        body: 'Marta Chávez envió un comprobante por Q 150.00.',
        data: const {'voucherId': 'v1', 'chargeId': '7'},
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      AppNotification(
        id: 'n2',
        type: NotificationTypes.userPendingValidation,
        title: 'Usuario por validar',
        body: 'Lucía Ramírez se registró y espera validación.',
        data: const {'userId': '3'},
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      AppNotification(
        id: 'n3',
        type: NotificationTypes.chargeCreated,
        title: 'Nuevo cobro',
        body: 'Se generó tu mensualidad de este mes.',
        data: const {'chargeId': '4'},
        createdAt: now.subtract(const Duration(days: 3)),
        readAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  int get _unread => _items.where((n) => n.unread).length;

  @override
  Future<NotificationPage> myNotifications({
    int page = 1,
    bool unreadOnly = false,
  }) async {
    await _wait();
    final all = [
      for (final n in _items)
        if (!unreadOnly || n.unread) n,
    ];
    return NotificationPage(
      items: pageOf(all, page, NotificationRepository.pageSize),
      unreadCount: _unread,
      hasNext: page * NotificationRepository.pageSize < all.length,
    );
  }

  @override
  Future<int> markAsRead({List<String>? ids, bool all = false}) async {
    await _wait();
    final now = DateTime.now();
    for (var i = 0; i < _items.length; i++) {
      if (all || (ids?.contains(_items[i].id) ?? false)) {
        _items[i] = _items[i].markedRead(now);
      }
    }
    return _unread;
  }

  /// Teléfonos registrados (para las pruebas).
  final devices = <String, String>{};

  @override
  Future<void> registerDevice(String token, String platform) async {
    await _wait();
    devices[token] = platform;
  }

  @override
  Future<void> unregisterDevice(String token) async {
    await _wait();
    devices.remove(token);
  }
}
