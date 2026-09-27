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

  String get fullName => '$firstName $firstLastName';
  bool get isAdmin => role == UserRole.admin;
}
