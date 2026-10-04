import 'package:flutter/widgets.dart';

import '../features/admin/presentation/admin_home_page.dart';
import '../features/auth/data/app_user.dart';
import '../features/billing/presentation/pending_profile_page.dart';
import '../features/family/presentation/family_page.dart';
import '../features/notifications/presentation/notification_host.dart';

/// Pantalla de inicio según el usuario:
/// - Padre que el club aún no valida: "Estamos configurando tu perfil".
/// - Con permisos de administración: panel de admin (sus secciones
///   dependen de cada permiso).
/// - Solo con "gestionar mis hijos": Mi familia.
///
/// Si la API no informa permisos (versión sin roles/permisos en `/me`),
/// se usa Mi familia, que es la experiencia base de todo usuario.
Widget homePageFor(AppUser user) {
  if (user.awaitingValidation) return PendingProfilePage(user: user);
  return user.permissions.isEmpty || user.managesOwnFamily
      ? FamilyPage(user: user)
      : AdminHomePage(user: user);
}

/// [homePageFor] con las notificaciones del sistema activas: al entrar pide
/// el permiso y avisa de lo nuevo mientras dure la sesión.
Widget homeFor(AppUser user) =>
    NotificationHost(user: user, child: homePageFor(user));
