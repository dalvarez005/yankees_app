import 'api_auth_repository.dart';
import '../../../core/access/permissions.dart';
import '../../billing/data/billing_models.dart';
import 'app_user.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Contrato de autenticación. La implementación real es
/// [ApiAuthRepository]; se elige en main.dart.
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

  /// Inicia sesión o crea la cuenta con Google. Devuelve null si el
  /// usuario cancela el selector de cuentas.
  Future<AppUser?> signInWithGoogle();

  /// Web: el botón de Google entrega el idToken directamente.
  Future<AppUser> signInWithGoogleIdToken(String idToken);

  /// Pide el código de recuperación. La API responde igual exista o no la
  /// cuenta, así que esto no confirma que el correo esté registrado.
  Future<void> sendPasswordReset(String email);

  /// Define la contraseña nueva con el código de 6 dígitos del correo.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Al abrir la app: devuelve el usuario si hay una sesión guardada válida.
  Future<AppUser?> restoreSession();

  /// Datos actuales del usuario con sesión, desde la API.
  Future<AppUser> fetchProfile();

  /// Actualiza nombres y apellidos del usuario con sesión.
  Future<AppUser> updateProfile(ProfileInput input);

  Future<void> signOut();
}

class ProfileInput {
  const ProfileInput({
    required this.firstName,
    required this.firstLastName,
    this.secondName,
    this.secondLastName,
  });

  final String firstName;
  final String? secondName;
  final String firstLastName;
  final String? secondLastName;
}

/// Implementación en memoria para desarrollar la UI sin backend.
/// Usuarios de prueba:
///   admin@yankees.com / admin123  (administrador)
///   padre@yankees.com / padre123  (padre / tutor)
///   nuevo@yankees.com / nuevo123  (padre sin validar: pantalla de espera)
class MockAuthRepository implements AuthRepository {
  final _users = <String, ({AppUser user, String password})>{
    'admin@yankees.com': (
      user: const AppUser(
        id: '1',
        email: 'admin@yankees.com',
        firstName: 'Administración',
        firstLastName: 'Yankees',
        roleName: 'SUPER_ADMIN',
        permissions: {...Permissions.admin, Permissions.ownDependents},
        billing: Billing(status: BillingStatus.notApplicable),
      ),
      password: 'admin123',
    ),
    'padre@yankees.com': (
      user: const AppUser(
        id: '2',
        email: 'padre@yankees.com',
        firstName: 'Carlos',
        firstLastName: 'Pérez',
        roleName: 'USER_BASE',
        permissions: {Permissions.ownDependents},
        billing: _active,
      ),
      password: 'padre123',
    ),
    'nuevo@yankees.com': (
      user: const AppUser(
        id: '3',
        email: 'nuevo@yankees.com',
        firstName: 'Lucía',
        firstLastName: 'Ramírez',
        roleName: 'USER_BASE',
        permissions: {Permissions.ownDependents},
        billing: Billing(status: BillingStatus.pending),
      ),
      password: 'nuevo123',
    ),
  };

  static const _active = Billing(
    status: BillingStatus.active,
    enrollmentFee: 250,
    monthlyFee: 150,
  );

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
    return _current = entry.user;
  }

  AppUser? _current;

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
      roleName: 'USER_BASE',
      permissions: const {Permissions.ownDependents},
      billing: _active,
    );
    _users[key] = (user: user, password: password);
    return _current = user;
  }

  @override
  Future<AppUser> signInWithGoogleIdToken(String idToken) async =>
      (await signInWithGoogle())!;

  @override
  Future<AppUser?> signInWithGoogle() async {
    await _latency();
    return _current = const AppUser(
      id: 'g-1',
      email: 'maria.lopez@gmail.com',
      firstName: 'María',
      firstLastName: 'López',
      roleName: 'USER_BASE',
      permissions: {Permissions.ownDependents},
      billing: _active,
    );
  }

  @override
  Future<void> sendPasswordReset(String email) => _latency();

  /// En el mock el código siempre es 123456.
  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _latency();
    final key = email.trim().toLowerCase();
    final entry = _users[key];
    if (entry == null || code != '123456') {
      throw const AuthException('El código no es válido o ya venció');
    }
    _users[key] = (user: entry.user, password: newPassword);
  }

  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<AppUser> fetchProfile() async {
    await _latency();
    final user = _current;
    if (user == null) throw const AuthException('No hay sesión');
    return user;
  }

  @override
  Future<AppUser> updateProfile(ProfileInput input) async {
    await _latency();
    final user = _current;
    if (user == null) throw const AuthException('No hay sesión');
    return _current = AppUser(
      id: user.id,
      email: user.email,
      roleName: user.roleName,
      permissions: user.permissions,
      billing: user.billing,
      firstName: input.firstName,
      secondName: input.secondName,
      firstLastName: input.firstLastName,
      secondLastName: input.secondLastName,
    );
  }

  @override
  Future<void> signOut() async {}
}
