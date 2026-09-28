class Validators {
  static final _email = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)*\.[a-zA-Z]{2,}$');
  static final _cui = RegExp(r'^\d{13}$');
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

  /// CUI guatemalteco: 13 dígitos (se aceptan espacios, como en el DPI).
  static String? cui(String? v) {
    final digits = v?.replaceAll(' ', '') ?? '';
    if (digits.isEmpty) return 'El CUI es obligatorio';
    if (!_cui.hasMatch(digits)) return 'El CUI debe tener 13 dígitos';
    return null;
  }

  /// Segundo nombre/apellido: opcional, pero si se escribe debe ser válido.
  static String? optionalName(String? v, String field) =>
      (v == null || v.trim().isEmpty) ? null : name(v, field);

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
