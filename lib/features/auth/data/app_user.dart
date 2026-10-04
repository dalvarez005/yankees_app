import '../../../core/access/permissions.dart';
import '../../billing/data/billing_models.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.firstLastName,
    this.roleName = '',
    this.permissions = const {},
    this.secondName,
    this.secondLastName,
    this.billing,
  });

  final String id;
  final String email;
  final String firstName;
  final String? secondName;
  final String firstLastName;
  final String? secondLastName;

  /// Rol y permisos vienen de `GET /api/User/me` (campo `access`).
  final String roleName;
  final Set<String> permissions;

  /// Perfil de cobro (`billing` de `/me`). null en sesiones guardadas antes
  /// de que existiera o si la API no lo manda: se trata como validado.
  final Billing? billing;

  /// Nombre corto para saludos: primer nombre y primer apellido.
  String get fullName => '$firstName $firstLastName'.trim();

  /// Nombre completo con segundos nombres/apellidos si los hay.
  String get legalName => [
    firstName,
    secondName,
    firstLastName,
    secondLastName,
  ].where((p) => p != null && p.trim().isNotEmpty).join(' ');

  /// Nombre para mostrar; si la API no lo devolvió, el correo.
  String get displayName => fullName.isEmpty ? email : fullName;

  String get initials {
    final letters = [
      firstName,
      firstLastName,
    ].where((p) => p.isNotEmpty).map((p) => p[0]).join();
    if (letters.isNotEmpty) return letters.toUpperCase();
    return email.isEmpty ? '?' : email[0].toUpperCase();
  }

  bool can(String permission) => permissions.contains(permission);

  /// Entra al panel de administración (tiene algún permiso de admin).
  bool get isAdmin => permissions.any(Permissions.admin.contains);

  /// Padre/madre/tutor: registra a sus hijos y paga cuotas. Los
  /// administradores quedan fuera de ese flujo aunque su rol tuviera el
  /// permiso (la API tampoco se lo concede).
  bool get managesOwnFamily => can(Permissions.ownDependents) && !isAdmin;

  /// Algunos endpoints de la API exigen el rol SUPER_ADMIN (no un permiso).
  bool get isSuperAdmin => roleName.trim().toUpperCase() == 'SUPER_ADMIN';

  /// Padre recién registrado que el club aún no valida: ve "Estamos
  /// configurando tu perfil". Los administradores están exentos.
  bool get awaitingValidation =>
      !isAdmin && !isSuperAdmin && (billing?.pending ?? false);

  /// Mismo usuario con otro rol/permisos (tras releer el perfil).
  AppUser withAccess({
    required String roleName,
    required Set<String> permissions,
  }) => AppUser(
    id: id,
    email: email,
    firstName: firstName,
    secondName: secondName,
    firstLastName: firstLastName,
    secondLastName: secondLastName,
    roleName: roleName,
    permissions: permissions,
    billing: billing,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'firstName': firstName,
    'secondName': secondName,
    'firstLastName': firstLastName,
    'secondLastName': secondLastName,
    'roleName': roleName,
    'permissions': permissions.toList(),
    if (billing != null) 'billing': billing!.toJson(),
  };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    firstName: json['firstName'] as String? ?? '',
    secondName: json['secondName'] as String?,
    firstLastName: json['firstLastName'] as String? ?? '',
    secondLastName: json['secondLastName'] as String?,
    roleName: json['roleName'] as String? ?? '',
    permissions: {...?(json['permissions'] as List?)?.cast<String>()},
    billing: json['billing'] is Map<String, dynamic>
        ? Billing.fromJson(json['billing'] as Map<String, dynamic>)
        : null,
  );
}
