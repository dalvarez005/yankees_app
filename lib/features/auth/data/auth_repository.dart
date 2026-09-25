import 'app_user.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Contrato de autenticación. Cuando elijamos backend (Firebase, Supabase,
/// API propia) se crea otra implementación y se cambia en [AuthRepository.instance].
abstract class AuthRepository {
  static AuthRepository instance = MockAuthRepository();

  Future<AppUser> signIn({required String email, required String password});

  Future<AppUser> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

/// Implementación en memoria para desarrollar la UI sin backend.
/// Usuarios de prueba:
///   admin@yankees.com / admin123  (administrador)
///   padre@yankees.com / padre123  (padre / tutor)
class MockAuthRepository implements AuthRepository {
  final _users = <String, ({AppUser user, String password})>{
    'admin@yankees.com': (
      user: const AppUser(
        id: '1',
        fullName: 'Administración Yankees',
        email: 'admin@yankees.com',
        phone: '',
        role: UserRole.admin,
      ),
      password: 'admin123',
    ),
    'padre@yankees.com': (
      user: const AppUser(
        id: '2',
        fullName: 'Carlos Pérez',
        email: 'padre@yankees.com',
        phone: '55555555',
        role: UserRole.parent,
      ),
      password: 'padre123',
    ),
  };

  Future<void> _latency() => Future.delayed(const Duration(milliseconds: 900));

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    await _latency();
    final entry = _users[email.trim().toLowerCase()];
    if (entry == null || entry.password != password) {
      throw const AuthException('Correo o contraseña incorrectos');
    }
    return entry.user;
  }

  @override
  Future<AppUser> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    await _latency();
    final key = email.trim().toLowerCase();
    if (_users.containsKey(key)) {
      throw const AuthException('Ya existe una cuenta con ese correo');
    }
    // Todo registro público es de padre/tutor; los admins los crea el club.
    final user = AppUser(
      id: '${_users.length + 1}',
      fullName: fullName.trim(),
      email: key,
      phone: phone.trim(),
      role: UserRole.parent,
    );
    _users[key] = (user: user, password: password);
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) => _latency();

  @override
  Future<void> signOut() async {}
}
