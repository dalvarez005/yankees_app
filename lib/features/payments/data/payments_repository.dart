import '../../../core/network/api_client.dart';
import '../../family/data/dependent.dart';
import '../../family/data/dependent_repository.dart';
import 'payment_models.dart';

class PaymentsException implements Exception {
  const PaymentsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Cargos, comprobantes y validación de pagos.
///
/// Padre: ve sus cargos y sube comprobantes. Admin con `pagos.asignar`
/// asigna cargos; con `pagos.validar` aprueba o rechaza comprobantes; con
/// `configuracion.gestionar` define el WhatsApp de contacto.
abstract class PaymentsRepository {
  /// Simulado hasta que la API tenga el módulo (ver docs/API_PAGOS.md).
  static PaymentsRepository instance = MockPaymentsRepository();

  // ---- Padre
  Future<List<Charge>> myCharges();
  Future<Charge> uploadVoucher(
    String chargeId, {
    required String filePath,
    String? reference,
  });
  Future<PaymentContact> contact();

  // ---- Admin
  Future<List<Charge>> charges({ChargeStatus? status, String? search});
  Future<List<ChargeTargetDependent>> searchDependents(String search);

  /// A un hijo ([dependentId]) o a todos los de una categoría
  /// ([categoryId]). Devuelve cuántos cargos se crearon.
  Future<int> assignCharge({
    required String concept,
    String? description,
    required double amount,
    DateTime? dueDate,
    String? dependentId,
    int? categoryId,
  });
  Future<void> cancelCharge(String chargeId);

  /// Cargos con comprobante esperando validación (más antiguos primero).
  Future<List<Charge>> reviewQueue();

  /// [comment] es obligatorio al rechazar.
  Future<Charge> reviewVoucher(
    String voucherId, {
    required bool approve,
    String? comment,
  });
  Future<PaymentContact> updateContact(PaymentContact contact);

  /// Headers para descargar la imagen de un comprobante (token).
  Future<Map<String, String>> fileHeaders();
  String fileUrl(String path);
}

class ApiPaymentsRepository implements PaymentsRepository {
  ApiPaymentsRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/Payment';

  @override
  Future<List<Charge>> myCharges() async =>
      _charges(await _call(() => _api.get('$_base/GetMyCharges')));

  @override
  Future<Charge> uploadVoucher(
    String chargeId, {
    required String filePath,
    String? reference,
  }) async {
    final json = await _call(
      () => _api.postFile(
        '$_base/UploadVoucher',
        fields: {
          'chargeId': chargeId,
          if (reference != null && reference.trim().isNotEmpty)
            'reference': reference.trim(),
        },
        fileField: 'file',
        filePath: filePath,
      ),
    );
    return _charge(json);
  }

  @override
  Future<PaymentContact> contact() async {
    final json = await _call(() => _api.get('$_base/GetContactSettings'));
    return PaymentContact.fromJson(
      json['settingsData'] as Map<String, dynamic>? ?? const {},
    );
  }

  @override
  Future<List<Charge>> charges({ChargeStatus? status, String? search}) async {
    final q = {
      'page': '1',
      'pageSize': '100',
      'status': ?status?.code,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final path = Uri(path: '$_base/GetChargeData', queryParameters: q);
    return _charges(await _call(() => _api.get(path.toString())));
  }

  @override
  Future<List<ChargeTargetDependent>> searchDependents(String search) async {
    final path = Uri(
      path: '/api/Dependent/GetAllDependents',
      queryParameters: {'search': search.trim(), 'page': '1', 'pageSize': '30'},
    );
    final json = await _call(() => _api.get(path.toString()));
    return (json['dependentData'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChargeTargetDependent.fromJson)
        .toList();
  }

  @override
  Future<int> assignCharge({
    required String concept,
    String? description,
    required double amount,
    DateTime? dueDate,
    String? dependentId,
    int? categoryId,
  }) async {
    final json = await _call(
      () => _api.post('$_base/ManageCharge', {
        'typeOperation': 'A',
        'chargeData': {
          'concept': concept.trim(),
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          'amount': amount,
          'dueDate': ?_day(dueDate),
          'dependentId': ?dependentId,
          'categoryId': ?categoryId,
        },
      }),
    );
    return (json['createdCount'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> cancelCharge(String chargeId) => _call(
    () => _api.post('$_base/ManageCharge', {
      'typeOperation': 'D',
      'chargeData': {'chargeId': chargeId},
    }),
  );

  @override
  Future<List<Charge>> reviewQueue() async => _charges(
    await _call(() => _api.get('$_base/GetPendingReviews?page=1&pageSize=100')),
  );

  @override
  Future<Charge> reviewVoucher(
    String voucherId, {
    required bool approve,
    String? comment,
  }) async {
    final json = await _call(
      () => _api.post('$_base/ReviewVoucher', {
        'voucherId': voucherId,
        'decision': approve ? 'A' : 'X',
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      }),
    );
    return _charge(json);
  }

  @override
  Future<PaymentContact> updateContact(PaymentContact contact) async {
    final json = await _call(
      () => _api.post('$_base/UpdateContactSettings', {
        'whatsappNumber': contact.whatsappNumber,
        'displayName': ?contact.displayName,
      }),
    );
    return PaymentContact.fromJson(
      json['settingsData'] as Map<String, dynamic>? ?? const {},
    );
  }

  @override
  Future<Map<String, String>> fileHeaders() => _api.authHeaders();

  @override
  String fileUrl(String path) =>
      path.startsWith('http') ? path : '${_api.baseUrl}$path';

  static String? _day(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';

  static List<Charge> _charges(Map<String, dynamic> json) =>
      (json['chargeData'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Charge.fromJson)
          .toList();

  static Charge _charge(Map<String, dynamic> json) =>
      Charge.fromJson(json['chargeData'] as Map<String, dynamic>? ?? const {});

  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on ApiException catch (e) {
      throw PaymentsException(e.message);
    }
  }
}

/// En memoria: permite probar todo el flujo (padre y admin en el mismo
/// teléfono) mientras la API no tenga el módulo de pagos. Los cargos de
/// ejemplo se generan para los hijos reales del usuario.
class MockPaymentsRepository implements PaymentsRepository {
  MockPaymentsRepository({this.latency = const Duration(milliseconds: 400)});

  final Duration latency;
  final _charges = <Charge>[];
  var _seeded = false;
  var _nextId = 1;
  var _contact = const PaymentContact(
    whatsappNumber: '50200000000',
    displayName: 'Tesorería del club',
  );

  Future<void> _wait() => Future.delayed(latency);

  Future<void> _seed() async {
    if (_seeded) return;
    // Si los hijos no cargan, sin ejemplos: el reintento vuelve a sembrar.
    List<Dependent> kids;
    try {
      kids = await DependentRepository.instance.list();
    } on DependentException catch (e) {
      throw PaymentsException(e.message);
    }
    _seeded = true;
    final now = DateTime.now();
    for (final d in kids) {
      final name = '${d.firstName} ${d.firstLastName}';
      _charges.addAll([
        Charge(
          id: '${_nextId++}',
          dependentId: d.id,
          dependentName: name,
          concept: 'Inscripción temporada 2026',
          description: 'Incluye seguro y carné del club.',
          amount: 250,
          dueDate: now.add(const Duration(days: 10)),
          status: ChargeStatus.pending,
          createdAt: now.subtract(const Duration(days: 5)),
          categoryName: d.categoryName,
          parentName: 'Padre de $name',
        ),
        Charge(
          id: '${_nextId++}',
          dependentId: d.id,
          dependentName: name,
          concept: 'Mensualidad de septiembre',
          amount: 100,
          dueDate: now.subtract(const Duration(days: 20)),
          status: ChargeStatus.paid,
          createdAt: now.subtract(const Duration(days: 40)),
          categoryName: d.categoryName,
          parentName: 'Padre de $name',
          paidAt: now.subtract(const Duration(days: 22)),
          voucher: Voucher(
            id: 'v${_nextId++}',
            status: VoucherStatus.approved,
            uploadedAt: now.subtract(const Duration(days: 23)),
            reference: 'Boleta 889231',
            reviewedAt: now.subtract(const Duration(days: 22)),
            reviewedBy: 'Tesorería',
          ),
        ),
      ]);
    }
  }

  int _index(String chargeId) {
    final i = _charges.indexWhere((c) => c.id == chargeId);
    if (i < 0) throw const PaymentsException('No se encontró el cobro.');
    return i;
  }

  @override
  Future<List<Charge>> myCharges() async {
    await _seed();
    await _wait();
    return [..._charges.where((c) => c.status != ChargeStatus.cancelled)];
  }

  @override
  Future<Charge> uploadVoucher(
    String chargeId, {
    required String filePath,
    String? reference,
  }) async {
    await _wait();
    final i = _index(chargeId);
    final c = _charges[i];
    if (!(c.status == ChargeStatus.pending ||
        c.status == ChargeStatus.rejected)) {
      throw const PaymentsException('Este cobro ya tiene un comprobante.');
    }
    return _charges[i] = c.copyWith(
      status: ChargeStatus.inReview,
      voucher: Voucher(
        id: 'v${_nextId++}',
        status: VoucherStatus.inReview,
        uploadedAt: DateTime.now(),
        localPath: filePath,
        reference: reference?.trim().isEmpty ?? true ? null : reference!.trim(),
      ),
    );
  }

  @override
  Future<PaymentContact> contact() async {
    await _wait();
    return _contact;
  }

  @override
  Future<List<Charge>> charges({ChargeStatus? status, String? search}) async {
    await _seed();
    await _wait();
    final q = search?.trim().toLowerCase() ?? '';
    return [
      ..._charges.where(
        (c) =>
            (status == null || c.status == status) &&
            (q.isEmpty ||
                c.dependentName.toLowerCase().contains(q) ||
                c.concept.toLowerCase().contains(q)),
      ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<ChargeTargetDependent>> searchDependents(String search) async {
    await _wait();
    final q = search.trim().toLowerCase();
    final kids = await DependentRepository.instance.list();
    return [
      for (final d in kids)
        if (q.isEmpty ||
            d.fullName.toLowerCase().contains(q) ||
            d.cui.contains(q))
          ChargeTargetDependent(
            id: d.id,
            name: d.fullName,
            categoryId: d.categoryId == 0 ? null : d.categoryId,
            categoryName: d.categoryName,
          ),
    ];
  }

  @override
  Future<int> assignCharge({
    required String concept,
    String? description,
    required double amount,
    DateTime? dueDate,
    String? dependentId,
    int? categoryId,
  }) async {
    await _seed();
    await _wait();
    final kids = await DependentRepository.instance.list();
    final targets = kids.where(
      (d) => dependentId != null
          ? d.id == dependentId
          : d.categoryId == categoryId,
    );
    for (final d in targets) {
      _charges.add(
        Charge(
          id: '${_nextId++}',
          dependentId: d.id,
          dependentName: '${d.firstName} ${d.firstLastName}',
          concept: concept.trim(),
          description: description?.trim().isEmpty ?? true
              ? null
              : description!.trim(),
          amount: amount,
          dueDate: dueDate,
          status: ChargeStatus.pending,
          createdAt: DateTime.now(),
          categoryName: d.categoryName,
        ),
      );
    }
    return targets.length;
  }

  @override
  Future<void> cancelCharge(String chargeId) async {
    await _wait();
    final i = _index(chargeId);
    if (_charges[i].status == ChargeStatus.paid) {
      throw const PaymentsException('No se puede anular un cobro pagado.');
    }
    _charges[i] = _charges[i].copyWith(status: ChargeStatus.cancelled);
  }

  @override
  Future<List<Charge>> reviewQueue() async {
    await _seed();
    await _wait();
    return [..._charges.where((c) => c.status == ChargeStatus.inReview)]
      ..sort((a, b) => a.voucher!.uploadedAt.compareTo(b.voucher!.uploadedAt));
  }

  @override
  Future<Charge> reviewVoucher(
    String voucherId, {
    required bool approve,
    String? comment,
  }) async {
    await _wait();
    if (!approve && (comment == null || comment.trim().isEmpty)) {
      throw const PaymentsException('Escribe el motivo del rechazo.');
    }
    final i = _charges.indexWhere((c) => c.voucher?.id == voucherId);
    if (i < 0) throw const PaymentsException('No se encontró el comprobante.');
    final c = _charges[i];
    final v = c.voucher!;
    final now = DateTime.now();
    return _charges[i] = c.copyWith(
      status: approve ? ChargeStatus.paid : ChargeStatus.rejected,
      paidAt: approve ? now : null,
      voucher: Voucher(
        id: v.id,
        status: approve ? VoucherStatus.approved : VoucherStatus.rejected,
        uploadedAt: v.uploadedAt,
        localPath: v.localPath,
        fileUrl: v.fileUrl,
        reference: v.reference,
        reviewComment: comment?.trim().isEmpty ?? true ? null : comment!.trim(),
        reviewedAt: now,
        reviewedBy: 'Tesorería',
      ),
    );
  }

  @override
  Future<PaymentContact> updateContact(PaymentContact contact) async {
    await _wait();
    return _contact = contact;
  }

  @override
  Future<Map<String, String>> fileHeaders() async => const {};

  @override
  String fileUrl(String path) => path;
}
