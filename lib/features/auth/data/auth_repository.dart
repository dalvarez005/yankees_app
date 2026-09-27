import 'app_user.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Contrato de autenticación. Cuando la API esté lista se crea otra
/// implementación y se cambia en [AuthRepository.instance].
abstract class AuthRepository {
  static AuthRepository instance = MockAuthRepository();

  Future<AppUser> signIn({required String email, required String password});

  /// Campos de la API: user_name (el correo), user_first_name,
  /// user_first_lastname, user_pass.
  Future<AppUser> register({
    required String email,
    required String firstName,
    required String firstLastName,
    required String password,
  });

  /// Inicia sesión o crea la cuenta con Google. En la implementación real:
  /// obtener el idToken con el paquete google_sign_in y mandarlo a la API.
  Future<AppUser> signInWithGoogle();

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
        email: 'admin@yankees.com',
        firstName: 'Administración',
        firstLastName: 'Yankees',
        role: UserRole.admin,
      ),
      password: 'admin123',
    ),
    'padre@yankees.com': (
      user: const AppUser(
        id: '2',
        email: 'padre@yankees.com',
        firstName: 'Carlos',
        firstLastName: 'Pérez',
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
    required String email,
    required String firstName,
    required String firstLastName,
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
      email: key,
      firstName: firstName.trim(),
      firstLastName: firstLastName.trim(),
      role: UserRole.parent,
    );
    _users[key] = (user: user, password: password);
    return user;
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    await _latency();
    return const AppUser(
      id: 'g-1',
      email: 'maria.lopez@gmail.com',
      firstName: 'María',
      firstLastName: 'López',
      role: UserRole.parent,
    );
  }

  @override
  Future<void> sendPasswordReset(String email) => _latency();

  @override
  Future<void> signOut() async {}
}
