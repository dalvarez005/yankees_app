enum UserRole { admin, parent }

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.firstLastName,
    required this.role,
  });

  final String id;
  final String email;
  final String firstName;
  final String firstLastName;
  final UserRole role;

  String get fullName => '$firstName $firstLastName'.trim();

  /// Nombre para mostrar; si la API no lo devolvió, el correo.
  String get displayName => fullName.isEmpty ? email : fullName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'firstName': firstName,
    'firstLastName': firstLastName,
    'role': role.name,
  };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    firstName: json['firstName'] as String? ?? '',
    firstLastName: json['firstLastName'] as String? ?? '',
    role: UserRole.values.asNameMap()[json['role']] ?? UserRole.parent,
  );
  bool get isAdmin => role == UserRole.admin;
}
