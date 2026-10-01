import '../../../core/network/api_client.dart';
import '../../../core/paging/page_of.dart';
import 'payment_models.dart';

class PaymentsException implements Exception {
  const PaymentsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Cobros, comprobantes y solvencia (docs/API_PAGOS.md §3.4–3.6).
///
/// Padre (perfil validado): sus cobros, su saldo y subir comprobantes.
/// Con `pagos.validar`: revisar comprobantes. Con `pagos.gestionar`: todos
/// los cobros, anular, insolventes, recordatorios y el reporte.
abstract class PaymentsRepository {
  /// En memoria hasta que main.dart ponga la de la API.
  static PaymentsRepository instance = MockPaymentsRepository();

  // ---- Padre
  /// Sin anulados, del más reciente al más antiguo.
  Future<List<Charge>> myCharges();
  Future<AccountBalance> myBalance();
  Future<Charge> uploadVoucher(
    String chargeId,
    VoucherForm form,
    VoucherUpload file,
  );

  // ---- Validación (pagos.validar)
  /// Cobros con comprobante en revisión (más antiguos primero).
  Future<List<Charge>> reviewQueue({int page = 1, int pageSize = 100});

  /// [comment] es obligatorio al rechazar (10 a 500 caracteres).
  Future<Charge> reviewVoucher(
    String voucherId, {
    required bool approve,
    String? comment,
  });

  // ---- Gestión (pagos.gestionar)
  Future<List<Charge>> charges({
    ChargeStatus? status,
    ChargeType? type,
    String? period,
    String? search,
    int page = 1,
    int pageSize = 100,
  });
  Future<Charge> cancelCharge(String chargeId);
  Future<InsolventPage> insolventUsers({
    int? categoryId,
    String? search,
    int page = 1,
    int pageSize = 100,
  });

  /// Sin [userIds] notifica a todos los insolventes.
  Future<NotifyResult> notifyInsolvents({
    List<String>? userIds,
    String? message,
  });
  Future<SolvencyReport> solvencyReport();

  /// Headers para descargar la imagen de un comprobante (token).
  Future<Map<String, String>> fileHeaders();
  String fileUrl(String path);
}

class ApiPaymentsRepository implements PaymentsRepository {
  ApiPaymentsRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/Payment';

  /// Límites del contrato para lo que genera la app.
  static const maxOcrText = 4000;
  static const maxEditSignals = 500;

  @override
  Future<List<Charge>> myCharges() async =>
      _charges(await _call(() => _api.get('$_base/GetMyCharges')));

  @override
  Future<AccountBalance> myBalance() async {
    final json = await _call(() => _api.get('$_base/GetMyBalance'));
    return AccountBalance.fromJson(
      json['balanceData'] as Map<String, dynamic>? ?? const {},
    );
  }

  @override
  Future<Charge> uploadVoucher(
    String chargeId,
    VoucherForm form,
    VoucherUpload file,
  ) async {
    final ocr = file.ocrText?.trim() ?? '';
    final signals = file.editSignals.join(';');
    final json = await _call(
      () => _api.postFile(
        '$_base/UploadVoucher',
        fields: {
          'chargeId': chargeId,
          'amount': form.amount.toStringAsFixed(2),
          'bankReference': form.bankReference.trim(),
          'description': form.description.trim(),
          'paymentDate': isoDay(form.paymentDate),
          if (ocr.isNotEmpty) 'ocrText': _cut(ocr, maxOcrText),
          if (signals.isNotEmpty) 'editSignals': _cut(signals, maxEditSignals),
        },
        fileField: 'file',
        bytes: file.bytes,
        fileName: file.fileName,
      ),
    );
    return _charge(json);
  }

  @override
  Future<List<Charge>> reviewQueue({int page = 1, int pageSize = 100}) async =>
      _charges(
        await _call(
          () => _api.get(
            '$_base/GetPendingReviews?page=$page&pageSize=$pageSize',
          ),
        ),
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
  Future<List<Charge>> charges({
    ChargeStatus? status,
    ChargeType? type,
    String? period,
    String? search,
    int page = 1,
    int pageSize = 100,
  }) async {
    final q = {
      'status': ?status?.code,
      'type': ?type?.code,
      'period': ?period,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': '$page',
      'pageSize': '$pageSize',
    };
    final path = Uri(path: '$_base/GetChargeData', queryParameters: q);
    return _charges(await _call(() => _api.get(path.toString())));
  }

  @override
  Future<Charge> cancelCharge(String chargeId) async => _charge(
    await _call(() => _api.post('$_base/CancelCharge', {'chargeId': chargeId})),
  );

  @override
  Future<InsolventPage> insolventUsers({
    int? categoryId,
    String? search,
    int page = 1,
    int pageSize = 100,
  }) async {
    final q = {
      'categoryId': ?categoryId?.toString(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': '$page',
      'pageSize': '$pageSize',
    };
    final path = Uri(path: '$_base/GetInsolventUsers', queryParameters: q);
    final json = await _call(() => _api.get(path.toString()));
    return InsolventPage(
      users: [
        for (final u
            in (json['userData'] as List? ?? const [])
                .whereType<Map<String, dynamic>>())
          InsolventUser.fromJson(u),
      ],
      totalRecords: (json['totalRecords'] as num?)?.toInt(),
      hasNext: json['hasNext'] == true,
    );
  }

  @override
  Future<NotifyResult> notifyInsolvents({
    List<String>? userIds,
    String? message,
  }) async {
    final text = message?.trim() ?? '';
    final json = await _call(
      () => _api.post('$_base/NotifyInsolvents', {
        'userIds': userIds,
        if (text.isNotEmpty) 'message': text,
      }),
    );
    return NotifyResult(
      notified: (json['notifiedCount'] as num?)?.toInt() ?? 0,
      skipped: (json['skippedCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<SolvencyReport> solvencyReport() async {
    final json = await _call(() => _api.get('$_base/GetSolvencyReport'));
    return SolvencyReport.fromJson(
      json['reportData'] as Map<String, dynamic>? ?? const {},
    );
  }

  @override
  Future<Map<String, String>> fileHeaders() => _api.authHeaders();

  @override
  String fileUrl(String path) =>
      path.startsWith('http') ? path : '${_api.baseUrl}$path';

  static String _cut(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

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

/// En memoria (modo sin API y pruebas): los cobros del usuario con sesión
/// ('me') y de otras familias para las vistas de admin.
class MockPaymentsRepository implements PaymentsRepository {
  MockPaymentsRepository({this.latency = const Duration(milliseconds: 400)}) {
    _seed();
  }

  final Duration latency;
  final _charges = <Charge>[];
  final _reminded = <String, DateTime>{};
  var _nextId = 1;

  /// Id del usuario con sesión en los datos simulados.
  static const me = 'me';

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  void _seed() {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final prev = DateTime(now.year, now.month - 1);
    Charge monthly(
      String user,
      String parent,
      DateTime m,
      ChargeStatus status, {
      Voucher? voucher,
    }) => Charge(
      id: '${_nextId++}',
      userId: user,
      type: ChargeType.monthly,
      concept: 'Mensualidad ${formatPeriod(periodOf(m)).toLowerCase()}',
      period: periodOf(m),
      amount: 150,
      dueDate: DateTime(m.year, m.month, 15),
      status: status,
      createdAt: m,
      parentName: parent,
      parentEmail: '${parent.split(' ').first.toLowerCase()}@correo.com',
      voucher: voucher,
      paidAt: status == ChargeStatus.paid
          ? m.add(const Duration(days: 5))
          : null,
      paidOnTime: status == ChargeStatus.paid ? true : null,
    );

    _charges.addAll([
      Charge(
        id: '${_nextId++}',
        userId: me,
        type: ChargeType.enrollment,
        concept: 'Inscripción',
        amount: 250,
        dueDate: now.add(const Duration(days: 10)),
        status: ChargeStatus.pending,
        createdAt: now.subtract(const Duration(days: 5)),
        parentName: 'Carlos Pérez',
        parentEmail: 'padre@yankees.com',
      ),
      monthly(
        me,
        'Carlos Pérez',
        prev,
        ChargeStatus.paid,
        voucher: Voucher(
          id: 'v${_nextId++}',
          status: VoucherStatus.approved,
          uploadedAt: prev.add(const Duration(days: 3)),
          amount: 150,
          bankReference: '889231',
          description: 'Depósito Banrural mensualidad',
          paymentDate: prev.add(const Duration(days: 2)),
          reviewedAt: prev.add(const Duration(days: 5)),
          reviewedBy: 'Tesorería',
        ),
      ),
      monthly(me, 'Carlos Pérez', month, ChargeStatus.pending),
      // Otras familias (vistas de admin).
      monthly('u2', 'Luis Istacuy', prev, ChargeStatus.pending),
      monthly('u2', 'Luis Istacuy', month, ChargeStatus.pending),
      monthly('u3', 'Ana Gómez', prev, ChargeStatus.rejected),
      monthly(
        'u4',
        'Marta Chávez',
        month,
        ChargeStatus.inReview,
        voucher: Voucher(
          id: 'v${_nextId++}',
          status: VoucherStatus.inReview,
          uploadedAt: now.subtract(const Duration(hours: 5)),
          amount: 150,
          bankReference: 'TRX-55120',
          description: 'Transferencia BI mensualidad',
          paymentDate: now.subtract(const Duration(days: 1)),
          suspectedEdit: true,
          editSignals: 'Software: Snapseed 2.0',
        ),
      ),
    ]);
  }

  /// Hijos de ejemplo de las familias insolventes.
  static const _kids = {
    'u2': [InsolventDependent(name: 'Pablo Istacuy', categoryId: 2)],
    'u3': [
      InsolventDependent(name: 'Sara Gómez', categoryId: 3),
      InsolventDependent(name: 'Iván Gómez', categoryId: 2),
    ],
    me: [InsolventDependent(name: 'Sofía Pérez', categoryId: 3)],
  };

  int _index(String chargeId) {
    final i = _charges.indexWhere((c) => c.id == chargeId);
    if (i < 0) throw const PaymentsException('No se encontró el cobro.');
    return i;
  }

  Iterable<Charge> get _mine => _charges.where(
    (c) => c.userId == me && c.status != ChargeStatus.cancelled,
  );

  @override
  Future<List<Charge>> myCharges() async {
    await _wait();
    return [..._mine]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<AccountBalance> myBalance() async {
    await _wait();
    return AccountBalance.fromCharges(_mine);
  }

  @override
  Future<Charge> uploadVoucher(
    String chargeId,
    VoucherForm form,
    VoucherUpload file,
  ) async {
    await _wait();
    final i = _index(chargeId);
    final c = _charges[i];
    if (c.status == ChargeStatus.inReview) {
      throw const PaymentsException(
        'Ya enviaste un comprobante; está en revisión.',
      );
    }
    if (!c.status.canUpload) {
      throw const PaymentsException('Este cobro ya está pagado.');
    }
    if ((form.amount - c.amount).abs() > 0.001) {
      throw const PaymentsException(
        'El monto del comprobante debe ser igual al del cobro.',
      );
    }
    final ref = form.bankReference.trim().toUpperCase();
    final used = _charges.any(
      (x) =>
          x.voucher != null &&
          x.voucher!.status != VoucherStatus.rejected &&
          x.voucher!.bankReference?.toUpperCase() == ref,
    );
    if (used) {
      throw const PaymentsException(
        'Ese número de boleta o transferencia ya se usó en otro comprobante.',
      );
    }
    return _charges[i] = c.copyWith(
      status: ChargeStatus.inReview,
      voucher: Voucher(
        id: 'v${_nextId++}',
        status: VoucherStatus.inReview,
        uploadedAt: DateTime.now(),
        localPath: file.previewPath,
        amount: form.amount,
        bankReference: form.bankReference.trim(),
        description: form.description.trim(),
        paymentDate: form.paymentDate,
        suspectedEdit: file.editSignals.isNotEmpty,
        editSignals: file.editSignals.isEmpty
            ? null
            : file.editSignals.join(';'),
      ),
    );
  }

  @override
  Future<List<Charge>> reviewQueue({int page = 1, int pageSize = 100}) async {
    await _wait();
    final all = [..._charges.where((c) => c.status == ChargeStatus.inReview)]
      ..sort((a, b) => a.voucher!.uploadedAt.compareTo(b.voucher!.uploadedAt));
    return pageOf(all, page, pageSize);
  }

  @override
  Future<Charge> reviewVoucher(
    String voucherId, {
    required bool approve,
    String? comment,
  }) async {
    await _wait();
    final note = comment?.trim() ?? '';
    if (!approve && note.length < 10) {
      throw const PaymentsException(
        'Escribe el motivo del rechazo (mínimo 10 caracteres).',
      );
    }
    final i = _charges.indexWhere((c) => c.voucher?.id == voucherId);
    if (i < 0) throw const PaymentsException('No se encontró el comprobante.');
    final c = _charges[i];
    if (c.status != ChargeStatus.inReview) {
      throw const PaymentsException(
        'Otro administrador ya revisó este comprobante.',
      );
    }
    final now = DateTime.now();
    final v = c.voucher!;
    return _charges[i] = c.copyWith(
      status: approve ? ChargeStatus.paid : ChargeStatus.rejected,
      paidAt: approve ? now : null,
      paidOnTime: approve
          ? c.dueDate == null || !v.uploadedAt.isAfter(_endOfDay(c.dueDate!))
          : null,
      voucher: v.reviewed(
        approve: approve,
        comment: note.isEmpty ? null : note,
        at: now,
        by: 'Tesorería',
      ),
    );
  }

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  @override
  Future<List<Charge>> charges({
    ChargeStatus? status,
    ChargeType? type,
    String? period,
    String? search,
    int page = 1,
    int pageSize = 100,
  }) async {
    await _wait();
    final q = search?.trim().toLowerCase() ?? '';
    final all = [
      ..._charges.where(
        (c) =>
            (status == null || c.status == status) &&
            (type == null || c.type == type) &&
            (period == null || c.period == period) &&
            (q.isEmpty ||
                (c.parentName ?? '').toLowerCase().contains(q) ||
                (c.parentEmail ?? '').toLowerCase().contains(q) ||
                c.concept.toLowerCase().contains(q)),
      ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return pageOf(all, page, pageSize);
  }

  @override
  Future<Charge> cancelCharge(String chargeId) async {
    await _wait();
    final i = _index(chargeId);
    final c = _charges[i];
    if (c.status == ChargeStatus.paid) {
      throw const PaymentsException('No se puede anular un cobro pagado.');
    }
    return _charges[i] = c.copyWith(
      status: ChargeStatus.cancelled,
      voucher: c.status == ChargeStatus.inReview
          ? c.voucher!.reviewed(
              approve: false,
              comment: 'Cobro anulado por el club',
              at: DateTime.now(),
            )
          : null,
    );
  }

  List<InsolventUser> _insolvents() {
    final byUser = <String, List<Charge>>{};
    for (final c in _charges.where(
      (c) =>
          c.overdue &&
          (c.status == ChargeStatus.pending ||
              c.status == ChargeStatus.rejected),
    )) {
      (byUser[c.userId ?? ''] ??= []).add(c);
    }
    return [
      for (final MapEntry(key: id, value: list) in byUser.entries)
        InsolventUser(
          userId: id,
          name: list.first.parentName ?? id,
          email: list.first.parentEmail ?? '',
          overdueAmount: list.fold(0, (s, c) => s + c.amount),
          overdueCharges: list.length,
          oldestDueDate: (list.map((c) => c.dueDate!).toList()..sort()).first,
          lastReminderAt: _reminded[id],
          dependents: _kids[id] ?? const [],
        ),
    ]..sort((a, b) => b.overdueAmount.compareTo(a.overdueAmount));
  }

  @override
  Future<InsolventPage> insolventUsers({
    int? categoryId,
    String? search,
    int page = 1,
    int pageSize = 100,
  }) async {
    await _wait();
    final q = search?.trim().toLowerCase() ?? '';
    final users = [
      for (final u in _insolvents())
        if ((categoryId == null ||
                u.dependents.any((d) => d.categoryId == categoryId)) &&
            (q.isEmpty ||
                u.name.toLowerCase().contains(q) ||
                u.email.toLowerCase().contains(q)))
          u,
    ];
    return InsolventPage(
      users: pageOf(users, page, pageSize),
      totalRecords: users.length,
      hasNext: page * pageSize < users.length,
    );
  }

  @override
  Future<NotifyResult> notifyInsolvents({
    List<String>? userIds,
    String? message,
  }) async {
    await _wait();
    final now = DateTime.now();
    final targets = userIds ?? [for (final u in _insolvents()) u.userId];
    var notified = 0;
    var skipped = 0;
    for (final id in targets) {
      final last = _reminded[id];
      if (last != null && now.difference(last) < const Duration(hours: 24)) {
        skipped++;
      } else {
        _reminded[id] = now;
        notified++;
      }
    }
    return NotifyResult(notified: notified, skipped: skipped);
  }

  @override
  Future<SolvencyReport> solvencyReport() async {
    await _wait();
    final users = {for (final c in _charges) c.userId};
    final insolvent = _insolvents();
    final period = periodOf(DateTime.now());
    return SolvencyReport(
      period: period,
      approvedUsers: users.length,
      solventUsers: users.length - insolvent.length,
      insolventUsers: insolvent.length,
      pendingValidationUsers: 1,
      overdueAmount: insolvent.fold(0, (s, u) => s + u.overdueAmount),
      collectedThisPeriod: _charges
          .where((c) => c.status == ChargeStatus.paid && c.period == period)
          .fold(0, (s, c) => s + c.amount),
      inReviewAmount: _charges
          .where((c) => c.status == ChargeStatus.inReview)
          .fold(0, (s, c) => s + c.amount),
    );
  }

  @override
  Future<Map<String, String>> fileHeaders() async => const {};

  @override
  String fileUrl(String path) => path;
}
