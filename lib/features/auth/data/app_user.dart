enum UserRole { admin, parent }

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
  });

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final UserRole role;

  bool get isAdmin => role == UserRole.admin;
}
