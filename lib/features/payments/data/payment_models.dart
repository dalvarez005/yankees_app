import '../../../core/format/formats.dart';

/// Estado de un cobro. Código de la API entre paréntesis.
enum ChargeStatus {
  /// Por pagar, sin comprobante (P).
  pending('P'),

  /// Comprobante subido, esperando que un admin lo valide (R).
  inReview('R'),

  /// El admin rechazó el último comprobante; se puede subir otro (X).
  rejected('X'),

  /// Comprobante aprobado: pagado (A).
  paid('A'),

  /// Anulado por un admin; no se cobra (C).
  cancelled('C');

  const ChargeStatus(this.code);
  final String code;

  static ChargeStatus fromCode(Object? code) => values.firstWhere(
    (s) => s.code == code?.toString(),
    orElse: () => ChargeStatus.pending,
  );

  /// Sigue pendiente de pago (cuenta para el saldo).
  bool get owes => this == pending || this == inReview || this == rejected;

  /// Se puede subir un comprobante.
  bool get canUpload => this == pending || this == rejected;
}

/// Tipo de cobro: inscripción (una vez) o mensualidad (una por período).
enum ChargeType {
  enrollment('I', 'Inscripción'),
  monthly('M', 'Mensualidad');

  const ChargeType(this.code, this.label);
  final String code;
  final String label;

  static ChargeType fromCode(Object? code) => values.firstWhere(
    (t) => t.code == code?.toString(),
    orElse: () => ChargeType.monthly,
  );
}

enum VoucherStatus {
  inReview('R'),
  approved('A'),
  rejected('X');

  const VoucherStatus(this.code);
  final String code;

  static VoucherStatus fromCode(Object? code) => values.firstWhere(
    (s) => s.code == code?.toString(),
    orElse: () => VoucherStatus.inReview,
  );
}

/// Comprobante de pago (`journal_payment`) subido por el padre.
class Voucher {
  const Voucher({
    required this.id,
    required this.status,
    required this.uploadedAt,
    this.fileUrl,
    this.localPath,
    this.amount,
    this.bankReference,
    this.description,
    this.paymentDate,
    this.suspectedEdit = false,
    this.editSignals,
    this.reviewComment,
    this.reviewedAt,
    this.reviewedBy,
  });

  final String id;
  final VoucherStatus status;
  final DateTime uploadedAt;

  /// Ruta de la API para descargar la imagen (requiere token).
  final String? fileUrl;

  /// Solo en modo simulado: la foto local.
  final String? localPath;

  /// Datos que escribió el padre.
  final double? amount;
  final String? bankReference;
  final String? description;
  final DateTime? paymentDate;

  /// Indicios de edición de la imagen (heurística; no es prueba).
  final bool suspectedEdit;

  /// Señales separadas por `;` tal como las guarda la API.
  final String? editSignals;

  /// Motivo del rechazo (obligatorio al rechazar) o nota al aprobar.
  final String? reviewComment;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  List<String> get editSignalList => [
    for (final s in (editSignals ?? '').split(';'))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  factory Voucher.fromJson(Map<String, dynamic> j) => Voucher(
    id: j['voucherId']?.toString() ?? '',
    status: VoucherStatus.fromCode(j['status']),
    uploadedAt: parseDate(j['uploadedAt']) ?? DateTime.now(),
    fileUrl: nonBlank(j['fileUrl']),
    amount: (j['amount'] as num?)?.toDouble(),
    bankReference: nonBlank(j['bankReference']),
    description: nonBlank(j['description']),
    paymentDate: parseDate(j['paymentDate']),
    suspectedEdit: j['suspectedEdit'] == true,
    editSignals: nonBlank(j['editSignals']),
    reviewComment: nonBlank(j['reviewComment']),
    reviewedAt: parseDate(j['reviewedAt']),
    reviewedBy: nonBlank(j['reviewedBy']),
  );

  Voucher reviewed({
    required bool approve,
    String? comment,
    required DateTime at,
    String? by,
  }) => Voucher(
    id: id,
    status: approve ? VoucherStatus.approved : VoucherStatus.rejected,
    uploadedAt: uploadedAt,
    fileUrl: fileUrl,
    localPath: localPath,
    amount: amount,
    bankReference: bankReference,
    description: description,
    paymentDate: paymentDate,
    suspectedEdit: suspectedEdit,
    editSignals: editSignals,
    reviewComment: comment,
    reviewedAt: at,
    reviewedBy: by,
  );
}

/// Cobro a un usuario (familia): inscripción o mensualidad de un período.
/// Los genera la API; nadie los asigna a mano.
class Charge {
  const Charge({
    required this.id,
    required this.type,
    required this.concept,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.userId,
    this.period,
    this.dueDate,
    this._overdue,
    this.paidAt,
    this.paidOnTime,
    this.parentName,
    this.parentEmail,
    this.voucher,
  });

  final String id;
  final String? userId;
  final ChargeType type;

  /// "Inscripción" o "Mensualidad octubre 2026" (lo arma la API).
  final String concept;

  /// `YYYY-MM` en mensualidades.
  final String? period;
  final double amount;
  final DateTime? dueDate;
  final ChargeStatus status;
  final bool? _overdue;
  final DateTime createdAt;
  final DateTime? paidAt;

  /// Comprobante subido a más tardar el día de vencimiento y aprobado.
  final bool? paidOnTime;

  /// Solo en vistas de admin: a quién se le cobra.
  final String? parentName;
  final String? parentEmail;

  /// Último comprobante subido (el vigente).
  final Voucher? voucher;

  /// Vencido y sin pagar. Lo calcula la API; si no viene, se deduce.
  /// Un cobro en revisión no cuenta como vencido (el padre ya pagó).
  bool get overdue =>
      _overdue ??
      ((status == ChargeStatus.pending || status == ChargeStatus.rejected) &&
          dueDate != null &&
          daysUntil(dueDate!) < 0);

  Charge copyWith({
    ChargeStatus? status,
    Voucher? voucher,
    DateTime? paidAt,
    bool? paidOnTime,
    double? amount,
  }) => Charge(
    id: id,
    userId: userId,
    type: type,
    concept: concept,
    period: period,
    amount: amount ?? this.amount,
    dueDate: dueDate,
    status: status ?? this.status,
    createdAt: createdAt,
    paidAt: paidAt ?? this.paidAt,
    paidOnTime: paidOnTime ?? this.paidOnTime,
    parentName: parentName,
    parentEmail: parentEmail,
    voucher: voucher ?? this.voucher,
  );

  factory Charge.fromJson(Map<String, dynamic> j) => Charge(
    id: j['chargeId']?.toString() ?? '',
    userId: nonBlank(j['userId']),
    type: ChargeType.fromCode(j['type']),
    concept: j['concept']?.toString() ?? '',
    period: nonBlank(j['period']),
    amount: (j['amount'] as num?)?.toDouble() ?? 0,
    dueDate: parseDate(j['dueDate']),
    status: ChargeStatus.fromCode(j['status']),
    overdue: j['overdue'] is bool ? j['overdue'] as bool : null,
    createdAt: parseDate(j['createdAt']) ?? DateTime.now(),
    paidAt: parseDate(j['paidAt']),
    paidOnTime: j['paidOnTime'] is bool ? j['paidOnTime'] as bool : null,
    parentName: nonBlank(j['parentName']),
    parentEmail: nonBlank(j['parentEmail']),
    voucher: j['voucher'] is Map<String, dynamic>
        ? Voucher.fromJson(j['voucher'] as Map<String, dynamic>)
        : null,
  );
}

/// Saldo del padre (`GetMyBalance`).
class AccountBalance {
  const AccountBalance({
    required this.solvent,
    this.totalOwed = 0,
    this.overdueAmount = 0,
    this.inReviewAmount = 0,
    this.nextDueDate,
  });

  /// Insolvente: algún cobro por pagar o rechazado ya venció.
  final bool solvent;
  final double totalOwed;
  final double overdueAmount;
  final double inReviewAmount;
  final DateTime? nextDueDate;

  /// Al día y sin nada por pagar.
  bool get clear => solvent && totalOwed <= 0;

  factory AccountBalance.fromJson(Map<String, dynamic> j) => AccountBalance(
    solvent: j['solvent'] != false,
    totalOwed: (j['totalOwed'] as num?)?.toDouble() ?? 0,
    overdueAmount: (j['overdueAmount'] as num?)?.toDouble() ?? 0,
    inReviewAmount: (j['inReviewAmount'] as num?)?.toDouble() ?? 0,
    nextDueDate: parseDate(j['nextDueDate']),
  );

  /// Mismo cálculo que la API, a partir de los cobros (modo simulado).
  factory AccountBalance.fromCharges(Iterable<Charge> charges) {
    final open = charges.where((c) => c.status.owes).toList();
    final overdue = open.where((c) => c.overdue);
    final upcoming =
        open
            .where((c) => c.status != ChargeStatus.inReview && !c.overdue)
            .map((c) => c.dueDate)
            .whereType<DateTime>()
            .toList()
          ..sort();
    double sum(Iterable<Charge> list) =>
        list.fold(0, (total, c) => total + c.amount);
    return AccountBalance(
      solvent: overdue.isEmpty,
      totalOwed: sum(open),
      overdueAmount: sum(overdue),
      inReviewAmount: sum(open.where((c) => c.status == ChargeStatus.inReview)),
      nextDueDate: upcoming.firstOrNull,
    );
  }
}

/// Datos del comprobante que escribe el padre. Todos obligatorios.
class VoucherForm {
  const VoucherForm({
    required this.amount,
    required this.bankReference,
    required this.description,
    required this.paymentDate,
  });

  final double amount;
  final String bankReference;
  final String description;
  final DateTime paymentDate;
}

/// Archivo listo para subir (ya comprimido) y lo que se detectó en el
/// original.
class VoucherUpload {
  const VoucherUpload({
    required this.bytes,
    this.fileName = 'comprobante.webp',
    this.ocrText,
    this.editSignals = const [],
    this.previewPath,
  });

  final List<int> bytes;
  final String fileName;

  /// Texto reconocido en el dispositivo (máx. 4000 al enviar).
  final String? ocrText;
  final List<String> editSignals;

  /// Foto original, para mostrarla en modo simulado.
  final String? previewPath;
}

/// Configuración de pagos (`GetPaymentSettings`).
class PaymentSettings {
  const PaymentSettings({
    this.defaultEnrollmentFee = 0,
    this.defaultMonthlyFee = 0,
    this.dueDay = 15,
    this.whatsappNumber = '',
    this.contactName,
  });

  final double defaultEnrollmentFee;
  final double defaultMonthlyFee;

  /// Día límite de la mensualidad (1 a 28) y días para pagar la inscripción.
  final int dueDay;

  /// Solo dígitos con código de país, p. ej. 50212345678; vacío si no hay.
  final String whatsappNumber;
  final String? contactName;

  bool get hasContact => whatsappNumber.isNotEmpty;

  factory PaymentSettings.fromJson(Map<String, dynamic> j) => PaymentSettings(
    defaultEnrollmentFee: (j['defaultEnrollmentFee'] as num?)?.toDouble() ?? 0,
    defaultMonthlyFee: (j['defaultMonthlyFee'] as num?)?.toDouble() ?? 0,
    dueDay: (j['dueDay'] as num?)?.toInt() ?? 15,
    whatsappNumber: (j['whatsappNumber']?.toString() ?? '').replaceAll(
      RegExp(r'\D'),
      '',
    ),
    contactName: nonBlank(j['contactName']),
  );

  Map<String, dynamic> toJson() => {
    'defaultEnrollmentFee': defaultEnrollmentFee,
    'defaultMonthlyFee': defaultMonthlyFee,
    'dueDay': dueDay,
    'whatsappNumber': whatsappNumber,
    'contactName': contactName ?? '',
  };
}

/// Hijo de un usuario insolvente (para filtrar por categoría).
class InsolventDependent {
  const InsolventDependent({
    required this.name,
    this.categoryId,
    this.categoryName,
  });

  final String name;
  final int? categoryId;
  final String? categoryName;

  factory InsolventDependent.fromJson(Map<String, dynamic> j) =>
      InsolventDependent(
        name: j['name']?.toString() ?? '',
        categoryId: (j['categoryId'] as num?)?.toInt(),
        categoryName: nonBlank(j['categoryName']),
      );
}

/// Usuario con al menos un cobro vencido (`GetInsolventUsers`).
class InsolventUser {
  const InsolventUser({
    required this.userId,
    required this.name,
    required this.email,
    required this.overdueAmount,
    this.overdueCharges = 0,
    this.oldestDueDate,
    this.lastReminderAt,
    this.dependents = const [],
  });

  final String userId;
  final String name;
  final String email;
  final double overdueAmount;
  final int overdueCharges;
  final DateTime? oldestDueDate;

  /// Último recordatorio enviado (máx. uno cada 24 h).
  final DateTime? lastReminderAt;
  final List<InsolventDependent> dependents;

  factory InsolventUser.fromJson(Map<String, dynamic> j) => InsolventUser(
    userId: j['userId']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    email: j['email']?.toString() ?? '',
    overdueAmount: (j['overdueAmount'] as num?)?.toDouble() ?? 0,
    overdueCharges: (j['overdueCharges'] as num?)?.toInt() ?? 0,
    oldestDueDate: parseDate(j['oldestDueDate']),
    lastReminderAt: parseDate(j['lastReminderAt']),
    dependents: [
      for (final d
          in (j['dependents'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
        InsolventDependent.fromJson(d),
    ],
  );
}

/// Página de insolventes con el total (para "Notificar a todos").
class InsolventPage {
  const InsolventPage({
    required this.users,
    this.totalRecords,
    this.hasNext = false,
  });

  final List<InsolventUser> users;
  final int? totalRecords;
  final bool hasNext;
}

/// Resultado de `NotifyInsolvents`.
class NotifyResult {
  const NotifyResult({required this.notified, required this.skipped});

  final int notified;

  /// Ya se les había notificado en las últimas 24 h.
  final int skipped;
}

/// Resumen de solvencia del club (`GetSolvencyReport`).
class SolvencyReport {
  const SolvencyReport({
    this.period,
    this.approvedUsers = 0,
    this.solventUsers = 0,
    this.insolventUsers = 0,
    this.pendingValidationUsers = 0,
    this.overdueAmount = 0,
    this.collectedThisPeriod = 0,
    this.inReviewAmount = 0,
  });

  final String? period;
  final int approvedUsers;
  final int solventUsers;
  final int insolventUsers;
  final int pendingValidationUsers;
  final double overdueAmount;
  final double collectedThisPeriod;
  final double inReviewAmount;

  factory SolvencyReport.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    double m(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return SolvencyReport(
      period: nonBlank(j['period']),
      approvedUsers: n('approvedUsers'),
      solventUsers: n('solventUsers'),
      insolventUsers: n('insolventUsers'),
      pendingValidationUsers: n('pendingValidationUsers'),
      overdueAmount: m('overdueAmount'),
      collectedThisPeriod: m('collectedThisPeriod'),
      inReviewAmount: m('inReviewAmount'),
    );
  }
}

/// Texto no vacío o null.
String? nonBlank(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Fecha ISO (con o sin hora) o null.
DateTime? parseDate(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString());

/// `yyyy-MM-dd` (fechas sin hora del contrato).
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const _monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "2026-10" → "Octubre 2026".
String formatPeriod(String period) {
  final parts = period.split('-');
  final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (month == null || month < 1 || month > 12) return period;
  final name = _monthNames[month - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} ${parts[0]}';
}

/// "2026-10" del mes de [d].
String periodOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
