enum UserRole { admin, parent }

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.firstLastName,
    required this.role,
    this.secondName,
    this.secondLastName,
  });

  final String id;
  final String email;
  final String firstName;
  final String? secondName;
  final String firstLastName;
  final String? secondLastName;
  final UserRole role;

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

  bool get isAdmin => role == UserRole.admin;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'firstName': firstName,
    'secondName': secondName,
    'firstLastName': firstLastName,
    'secondLastName': secondLastName,
    'role': role.name,
  };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    firstName: json['firstName'] as String? ?? '',
    secondName: json['secondName'] as String?,
    firstLastName: json['firstLastName'] as String? ?? '',
    secondLastName: json['secondLastName'] as String?,
    role: UserRole.values.asNameMap()[json['role']] ?? UserRole.parent,
  );
}
