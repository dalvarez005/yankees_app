class Validators {
  static final _email = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)*\.[a-zA-Z]{2,}$');
  static final _name = RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ' -]+$");

  static String? required(String? v, [String field = 'Este campo']) =>
      (v == null || v.trim().isEmpty) ? '$field es obligatorio' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
    if (!_email.hasMatch(v.trim())) return 'Correo no válido';
    return null;
  }

  /// Nombre o apellido: solo letras (con tildes), espacios, apóstrofo o guion.
  static String? name(String? v, String field) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return '$field es obligatorio';
    if (value.length < 2) return '$field es muy corto';
    if (!_name.hasMatch(value)) return '$field solo puede tener letras';
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Ingresa tu contraseña';
    if (v.length < 6) return 'Mínimo 6 caracteres';
    return null;
  }

  static String? confirmPassword(String? v, String password) {
    if (v == null || v.isEmpty) return 'Confirma tu contraseña';
    if (v != password) return 'Las contraseñas no coinciden';
    return null;
  }
}
