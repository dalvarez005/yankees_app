import '../../../core/paging/page_of.dart';
import '../../../core/network/api_client.dart';
import 'billing_models.dart';

class BillingException implements Exception {
  const BillingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Validación de usuarios nuevos y sus cuotas (docs/API_PAGOS.md §3.2).
/// Requiere `usuarios.validar`.
abstract class BillingRepository {
  static BillingRepository instance = MockBillingRepository();

  /// Los más antiguos primero.
  Future<List<PendingUser>> pendingUsers({
    String? search,
    int page = 1,
    int pageSize = 100,
  });

  /// Pasa el perfil a validado y crea el cobro de inscripción.
  Future<Billing> validateUser(
    String userId, {
    required double enrollmentFee,
    required double monthlyFee,
  });

  /// La mensualidad nueva aplica desde el próximo período.
  Future<Billing> updateUserFees(
    String userId, {
    double? enrollmentFee,
    double? monthlyFee,
  });
  Future<Billing> userBilling(String userId);
}

class ApiBillingRepository implements BillingRepository {
  ApiBillingRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/Billing';

  @override
  Future<List<PendingUser>> pendingUsers({
    String? search,
    int page = 1,
    int pageSize = 100,
  }) async {
    final q = search?.trim() ?? '';
    final path = Uri(
      path: '$_base/GetPendingUsers',
      queryParameters: {'page': '$page', 'pageSize': '$pageSize', 'search': q},
    );
    final json = await _call(() => _api.get(path.toString()));
    return [
      for (final u
          in (json['userData'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
        PendingUser.fromJson(u),
    ];
  }

  @override
  Future<Billing> validateUser(
    String userId, {
    required double enrollmentFee,
    required double monthlyFee,
  }) async => _billing(
    await _call(
      () => _api.post('$_base/ValidateUser', {
        'userId': userId,
        'enrollmentFee': enrollmentFee,
        'monthlyFee': monthlyFee,
      }),
    ),
  );

  @override
  Future<Billing> updateUserFees(
    String userId, {
    double? enrollmentFee,
    double? monthlyFee,
  }) async => _billing(
    await _call(
      () => _api.post('$_base/UpdateUserFees', {
        'userId': userId,
        'enrollmentFee': ?enrollmentFee,
        'monthlyFee': ?monthlyFee,
      }),
    ),
  );

  @override
  Future<Billing> userBilling(String userId) async => _billing(
    await _call(
      () => _api.get('$_base/GetUserBilling/${Uri.encodeComponent(userId)}'),
    ),
  );

  static Billing _billing(Map<String, dynamic> json) => Billing.fromJson(
    json['billingData'] as Map<String, dynamic>? ?? const {},
  );

  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on ApiException catch (e) {
      throw BillingException(e.message);
    }
  }
}

/// En memoria (modo sin API y pruebas).
class MockBillingRepository implements BillingRepository {
  MockBillingRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;

  final _pending = <PendingUser>[
    PendingUser(
      id: '3',
      email: 'nuevo@yankees.com',
      firstName: 'Lucía',
      firstLastName: 'Ramírez',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      dependentsCount: 1,
    ),
  ];
  final _profiles = <String, Billing>{};

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  static void _check(double? fee) {
    if (fee != null && (fee <= 0 || fee > 100000)) {
      throw const BillingException(
        'El monto debe ser mayor a Q 0 y hasta Q 100,000.',
      );
    }
  }

  @override
  Future<List<PendingUser>> pendingUsers({
    String? search,
    int page = 1,
    int pageSize = 100,
  }) async {
    await _wait();
    final q = search?.trim().toLowerCase() ?? '';
    final all = [
      for (final u in _pending)
        if (q.isEmpty ||
            u.name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q))
          u,
    ];
    return pageOf(all, page, pageSize);
  }

  @override
  Future<Billing> validateUser(
    String userId, {
    required double enrollmentFee,
    required double monthlyFee,
  }) async {
    await _wait();
    _check(enrollmentFee);
    _check(monthlyFee);
    final before = _pending.length;
    _pending.removeWhere((u) => u.id == userId);
    if (_pending.length == before) {
      throw const BillingException(
        'Este usuario ya fue validado. Actualiza la lista.',
      );
    }
    return _profiles[userId] = Billing(
      status: BillingStatus.active,
      userId: userId,
      enrollmentFee: enrollmentFee,
      monthlyFee: monthlyFee,
      approvedBy: 'Tú',
      approvedAt: DateTime.now(),
    );
  }

  @override
  Future<Billing> updateUserFees(
    String userId, {
    double? enrollmentFee,
    double? monthlyFee,
  }) async {
    await _wait();
    _check(enrollmentFee);
    _check(monthlyFee);
    final current = await userBilling(userId);
    return _profiles[userId] = Billing(
      status: current.status,
      userId: userId,
      enrollmentFee: enrollmentFee ?? current.enrollmentFee,
      monthlyFee: monthlyFee ?? current.monthlyFee,
      approvedBy: current.approvedBy,
      approvedAt: current.approvedAt,
      solvent: current.solvent,
      overdueAmount: current.overdueAmount,
    );
  }

  @override
  Future<Billing> userBilling(String userId) async {
    await _wait();
    if (_pending.any((u) => u.id == userId)) {
      return Billing(status: BillingStatus.pending, userId: userId);
    }
    return _profiles[userId] ??
        Billing(
          status: BillingStatus.active,
          userId: userId,
          enrollmentFee: 250,
          monthlyFee: 150,
        );
  }
}
