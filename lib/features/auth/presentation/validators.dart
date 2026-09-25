class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? v, [String field = 'Este campo']) =>
      (v == null || v.trim().isEmpty) ? '$field es obligatorio' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
    if (!_email.hasMatch(v.trim())) return 'Correo no válido';
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Ingresa tu contraseña';
    if (v.length < 6) return 'Mínimo 6 caracteres';
    return null;
  }

  static String? phone(String? v) {
    final digits = v?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (digits.isEmpty) return 'Ingresa tu teléfono';
    if (digits.length < 8) return 'Teléfono no válido';
    return null;
  }
}
