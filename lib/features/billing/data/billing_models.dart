/// Estado del perfil de cobro (`billing_profile.status`).
enum BillingStatus {
  /// Recién registrado: el club aún no le definió cuotas (P).
  pending('P'),

  /// Validado: se le generan cobros (A).
  active('A'),

  /// Exento (tiene permisos de administración): no se le cobra (N).
  notApplicable('N');

  const BillingStatus(this.code);
  final String code;

  /// Un código desconocido se trata como "no aplica" para no bloquear.
  static BillingStatus fromCode(Object? code) => values.firstWhere(
    (s) => s.code == code?.toString().toUpperCase(),
    orElse: () => BillingStatus.notApplicable,
  );
}

/// Perfil de cobro de un usuario: `billing` de `/me` o `billingData` de
/// `/api/Billing/*`. Con [BillingStatus.pending] o
/// [BillingStatus.notApplicable] los montos pueden venir null.
class Billing {
  const Billing({
    required this.status,
    this.userId,
    this.enrollmentFee,
    this.monthlyFee,
    this.solvent = true,
    this.overdueAmount = 0,
    this.approvedBy,
    this.approvedAt,
  });

  final BillingStatus status;
  final String? userId;
  final double? enrollmentFee;
  final double? monthlyFee;
  final bool solvent;
  final double overdueAmount;

  /// Quién lo validó y cuándo (solo en `billingData`).
  final String? approvedBy;
  final DateTime? approvedAt;

  bool get pending => status == BillingStatus.pending;

  factory Billing.fromJson(Map<String, dynamic> j) => Billing(
    status: BillingStatus.fromCode(j['status']),
    userId: j['userId']?.toString(),
    enrollmentFee: (j['enrollmentFee'] as num?)?.toDouble(),
    monthlyFee: (j['monthlyFee'] as num?)?.toDouble(),
    solvent: j['solvent'] != false,
    overdueAmount: (j['overdueAmount'] as num?)?.toDouble() ?? 0,
    approvedBy: j['approvedBy']?.toString(),
    approvedAt: j['approvedAt'] == null
        ? null
        : DateTime.tryParse(j['approvedAt'].toString()),
  );

  /// Lo que se guarda en la sesión junto al usuario.
  Map<String, dynamic> toJson() => {
    'status': status.code,
    'enrollmentFee': enrollmentFee,
    'monthlyFee': monthlyFee,
    'solvent': solvent,
    'overdueAmount': overdueAmount,
  };
}

/// Usuario recién registrado esperando que el club lo valide.
class PendingUser {
  const PendingUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.firstLastName,
    this.createdAt,
    this.dependentsCount = 0,
  });

  final String id;
  final String email;
  final String firstName;
  final String firstLastName;
  final DateTime? createdAt;
  final int dependentsCount;

  String get name {
    final n = '$firstName $firstLastName'.trim();
    return n.isEmpty ? email : n;
  }

  factory PendingUser.fromJson(Map<String, dynamic> j) => PendingUser(
    id: j['userId']?.toString() ?? '',
    email: j['email']?.toString() ?? '',
    firstName: j['firstName']?.toString().trim() ?? '',
    firstLastName: j['firstLastName']?.toString().trim() ?? '',
    createdAt: j['createdAt'] == null
        ? null
        : DateTime.tryParse(j['createdAt'].toString()),
    dependentsCount: (j['dependentsCount'] as num?)?.toInt() ?? 0,
  );
}
