import '../../../core/format/formats.dart';

/// Estado de un cargo. Código de la API entre paréntesis.
enum ChargeStatus {
  /// Asignado y sin comprobante (P).
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

/// Comprobante de pago subido por el padre para un cargo.
class Voucher {
  const Voucher({
    required this.id,
    required this.status,
    required this.uploadedAt,
    this.fileUrl,
    this.localPath,
    this.reference,
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

  /// Número de boleta o transferencia que escribe el padre (opcional).
  final String? reference;

  /// Motivo del rechazo (obligatorio al rechazar) o nota al aprobar.
  final String? reviewComment;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  factory Voucher.fromJson(Map<String, dynamic> j) => Voucher(
    id: j['voucherId']?.toString() ?? '',
    status: VoucherStatus.fromCode(j['status']),
    uploadedAt: _date(j['uploadedAt']) ?? DateTime.now(),
    fileUrl: _text(j['fileUrl']),
    reference: _text(j['reference']),
    reviewComment: _text(j['reviewComment']),
    reviewedAt: _date(j['reviewedAt']),
    reviewedBy: _text(j['reviewedBy']),
  );
}

/// Monto que un admin asigna a un hijo (inscripción, mensualidad, uniforme…).
class Charge {
  const Charge({
    required this.id,
    required this.dependentId,
    required this.dependentName,
    required this.concept,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.description,
    this.dueDate,
    this.categoryName,
    this.parentName,
    this.parentEmail,
    this.voucher,
    this.paidAt,
  });

  final String id;
  final String dependentId;
  final String dependentName;
  final String concept;
  final String? description;
  final double amount;
  final DateTime? dueDate;
  final ChargeStatus status;
  final DateTime createdAt;
  final String? categoryName;

  /// Solo en vistas de admin: a quién se le cobra.
  final String? parentName;
  final String? parentEmail;

  /// Último comprobante subido (el vigente).
  final Voucher? voucher;
  final DateTime? paidAt;

  /// Vencido y todavía sin pagar.
  bool get overdue => status.owes && dueDate != null && daysUntil(dueDate!) < 0;

  Charge copyWith({ChargeStatus? status, Voucher? voucher, DateTime? paidAt}) =>
      Charge(
        id: id,
        dependentId: dependentId,
        dependentName: dependentName,
        concept: concept,
        description: description,
        amount: amount,
        dueDate: dueDate,
        status: status ?? this.status,
        createdAt: createdAt,
        categoryName: categoryName,
        parentName: parentName,
        parentEmail: parentEmail,
        voucher: voucher ?? this.voucher,
        paidAt: paidAt ?? this.paidAt,
      );

  factory Charge.fromJson(Map<String, dynamic> j) => Charge(
    id: j['chargeId']?.toString() ?? '',
    dependentId: j['dependentId']?.toString() ?? '',
    dependentName: j['dependentName']?.toString() ?? '',
    concept: j['concept']?.toString() ?? '',
    description: _text(j['description']),
    amount: (j['amount'] as num?)?.toDouble() ?? 0,
    dueDate: _date(j['dueDate']),
    status: ChargeStatus.fromCode(j['status']),
    createdAt: _date(j['createdAt']) ?? DateTime.now(),
    categoryName: _text(j['categoryName']),
    parentName: _text(j['parentName']),
    parentEmail: _text(j['parentEmail']),
    voucher: j['voucher'] is Map<String, dynamic>
        ? Voucher.fromJson(j['voucher'] as Map<String, dynamic>)
        : null,
    paidAt: _date(j['paidAt']),
  );
}

/// Resumen del padre: cuánto debe y si está solvente.
class Balance {
  const Balance(this.charges);

  final List<Charge> charges;

  List<Charge> get open => [...charges.where((c) => c.status.owes)];
  List<Charge> get paid => [
    ...charges.where((c) => c.status == ChargeStatus.paid),
  ];

  double get totalOwed => open.fold(0, (sum, c) => sum + c.amount);
  double get totalInReview => open
      .where((c) => c.status == ChargeStatus.inReview)
      .fold(0, (sum, c) => sum + c.amount);

  /// Solvente: nada pendiente (lo que está en revisión aún no cuenta).
  bool get solvent => open.isEmpty;

  /// Solvencia de un hijo en particular.
  bool solventFor(String dependentId) =>
      !open.any((c) => c.dependentId == dependentId);

  double owedBy(String dependentId) => open
      .where((c) => c.dependentId == dependentId)
      .fold(0, (sum, c) => sum + c.amount);
}

/// Contacto al que el padre escribe si le rechazan un comprobante.
class PaymentContact {
  const PaymentContact({required this.whatsappNumber, this.displayName});

  /// Solo dígitos con código de país, p. ej. 50212345678.
  final String whatsappNumber;

  /// Nombre a mostrar ("Tesorería del club").
  final String? displayName;

  bool get configured => whatsappNumber.isNotEmpty;

  factory PaymentContact.fromJson(Map<String, dynamic> j) => PaymentContact(
    whatsappNumber: (j['whatsappNumber']?.toString() ?? '').replaceAll(
      RegExp(r'\D'),
      '',
    ),
    displayName: _text(j['displayName']),
  );
}

/// Hijo al que se le puede asignar un cargo (búsqueda del admin).
class ChargeTargetDependent {
  const ChargeTargetDependent({
    required this.id,
    required this.name,
    this.categoryId,
    this.categoryName,
    this.parentName,
  });

  final String id;
  final String name;
  final int? categoryId;
  final String? categoryName;
  final String? parentName;

  factory ChargeTargetDependent.fromJson(Map<String, dynamic> j) =>
      ChargeTargetDependent(
        id: j['dependentId']?.toString() ?? '',
        name: [
          j['firstName'],
          j['firstLastName'],
        ].where((p) => p != null && '$p'.trim().isNotEmpty).join(' '),
        categoryId: (j['categoryId'] as num?)?.toInt(),
        categoryName: _text(j['categoryName']),
        parentName: _text(j['parentName']),
      );
}

String? _text(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString());
