/// Códigos de permiso de la API (tabla `permission`, catálogo del contrato
/// v2). La app muestra u oculta pantallas según los permisos del rol.
///
/// Roles y permisos no son un permiso: solo los gestiona SUPER_ADMIN
/// (ver [AppUser.isSuperAdmin]).
abstract final class Permissions {
  static const usersView = 'usuarios.ver';
  static const usersManage = 'usuarios.gestionar';
  static const usersValidate = 'usuarios.validar';
  static const categoriesManage = 'categorias.gestionar';
  static const playersView = 'jugadores.ver';
  static const paymentsReview = 'pagos.validar';
  static const paymentsManage = 'pagos.gestionar';
  static const settingsManage = 'configuracion.gestionar';
  static const ownDependents = 'hijos.gestionar_propios';

  /// Con cualquiera de estos el usuario entra al panel de administración
  /// (y queda exento de cobros).
  static const admin = {
    usersView,
    usersManage,
    usersValidate,
    categoriesManage,
    playersView,
    paymentsReview,
    paymentsManage,
    settingsManage,
  };
}

/// Nombres legibles de los roles del sistema (los demás se muestran tal cual).
String roleLabel(String roleName) => switch (roleName) {
  'SUPER_ADMIN' => 'Super admin',
  'USER_BASE' => 'Usuario',
  'DEFAULT' => 'Usuario nuevo',
  _ => roleName,
};
