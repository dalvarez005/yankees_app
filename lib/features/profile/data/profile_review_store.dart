import '../../auth/data/app_user.dart';

/// Cuándo pedir "Confirma tus datos".
///
/// Solo pasa con cuentas de Google: si Google no manda nombre o apellido,
/// la API guarda valores de relleno (el correo como nombre, "GOOGLE" como
/// apellido). Se decide con los datos de la cuenta en el servidor, no con
/// algo guardado en el teléfono: una vez confirmados, ningún dispositivo
/// los vuelve a pedir. Quien se registra con correo ya escribió su nombre.
abstract final class ProfileReview {
  static bool needed(AppUser user) =>
      user.firstName.trim().isEmpty ||
      user.firstLastName.trim().isEmpty ||
      isPlaceholder(user.firstName, user) ||
      isPlaceholder(user.firstLastName, user);

  /// Valores que la API pone cuando Google no manda el dato. No sirven como
  /// nombre real.
  static bool isPlaceholder(String? value, AppUser user) {
    final v = value?.trim().toLowerCase() ?? '';
    return v == 'google' || v == user.email.toLowerCase() || v.contains('@');
  }
}
