/// Códigos de permiso de la API (tabla `permission`). La app muestra u
/// oculta pantallas según los permisos del rol del usuario.
abstract final class Permissions {
  static const usersView = 'usuarios.ver';
  static const usersManage = 'usuarios.gestionar';
  static const rolesManage = 'roles.gestionar';
  static const categoriesManage = 'categorias.gestionar';
  static const ownDependents = 'hijos.gestionar_propios';
  static const chargesAssign = 'pagos.asignar';
  static const paymentsReview = 'pagos.validar';
  static const settingsManage = 'configuracion.gestionar';

  /// Con cualquiera de estos el usuario entra al panel de administración.
  static const admin = {
    usersView,
    usersManage,
    rolesManage,
    categoriesManage,
    chargesAssign,
    paymentsReview,
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
