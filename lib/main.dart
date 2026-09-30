import 'package:flutter/material.dart';

import 'app/app_theme.dart';
import 'app/env.dart';
import 'app/routes.dart';
import 'core/network/api_client.dart';
import 'core/widgets/feedback.dart';
import 'core/session/session_manager.dart';
import 'core/session/session_store.dart';
import 'features/auth/data/api_auth_repository.dart';
import 'features/auth/data/app_user.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/google_id_token_provider.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/register_page.dart';
import 'features/family/data/dependent.dart';
import 'features/family/data/dependent_repository.dart';
import 'features/family/presentation/family_page.dart';
import 'core/access/permissions.dart';
import 'features/admin/data/admin_repository.dart';
import 'features/admin/presentation/admin_home_page.dart';
import 'features/categories/data/category_repository.dart';
import 'features/payments/data/payments_repository.dart';
import 'features/profile/data/profile_review_store.dart';
import 'features/profile/presentation/confirm_profile_page.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.useMock) {
    final api = ApiClient(baseUrl: Env.apiBaseUrl);
    final session = SessionManager(api: api, store: SecureSessionStore())
      ..onSessionExpired = _onSessionExpired;
    api.authenticator = session;
    AuthRepository.instance = ApiAuthRepository(
      api: api,
      session: session,
      google: GoogleSignInIdTokenProvider(),
      // Recuperar contraseña aún no existe en la API: se simula.
      pending: MockAuthRepository(),
    );
    DependentRepository.instance = ApiDependentRepository(api);
    CategoryRepository.instance = ApiCategoryRepository(api);
    AdminRepository.instance = ApiAdminRepository(api);
    if (Env.paymentsApi) {
      PaymentsRepository.instance = ApiPaymentsRepository(api);
    }
  }

  if (Env.useMock) await _seedMockFamily();

  // Si quedó una sesión guardada, se entra directo sin pedir login (salvo
  // que falte confirmar los datos del perfil).
  var user = await AuthRepository.instance.restoreSession();
  if (user != null) {
    // Rol y permisos actuales: un admin pudo cambiarlos desde la última vez.
    try {
      user = await AuthRepository.instance.fetchProfile();
    } on AuthException {
      // Sin conexión se usan los guardados en la sesión.
    }
  }
  final review =
      user != null && await ProfileReviewStore.instance.needsReview(user);
  runApp(YankeesApp(initialUser: user, reviewProfile: review));
}

/// Modo sin API: dos hijos de ejemplo para que se vean cobros y pagos.
Future<void> _seedMockFamily() async {
  final repo = DependentRepository.instance;
  for (final (cui, name, category) in [
    ('3004013889191', 'Sofía', 3),
    ('3004013889192', 'Mateo', 2),
  ]) {
    await repo.add(
      DependentInput(
        cui: cui,
        firstName: name,
        firstLastName: 'Castro',
        categoryId: category,
      ),
    );
  }
}

/// La API rechazó el refresh token: se vuelve al login avisando.
void _onSessionExpired() {
  _navigatorKey.currentState?.pushNamedAndRemoveUntil(
    Routes.login,
    (_) => false,
  );
  // Tras el primer frame de la nueva ruta, para que el aviso quede encima.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final overlay = _navigatorKey.currentState?.overlay;
    if (overlay != null) {
      showToast(
        overlay,
        'Tu sesión expiró. Inicia sesión de nuevo.',
        error: true,
      );
    }
  });
}

class YankeesApp extends StatelessWidget {
  const YankeesApp({super.key, this.initialUser, this.reviewProfile = false});

  /// Usuario de una sesión restaurada; null abre el login.
  final AppUser? initialUser;

  /// Abrir en "Confirma tus datos" en vez del inicio.
  final bool reviewProfile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Club Yankees',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: _navigatorKey,
      onGenerateInitialRoutes: (_) => [
        initialUser == null
            ? _route(const RouteSettings(name: Routes.login))
            : _route(
                RouteSettings(
                  name: reviewProfile ? Routes.confirmProfile : Routes.home,
                  arguments: initialUser,
                ),
              ),
      ],
      onGenerateRoute: _route,
    );
  }

  static Route<void> _route(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      Routes.register => const RegisterPage(),
      Routes.home => _homeFor(settings.arguments! as AppUser),
      Routes.confirmProfile => ConfirmProfilePage(
        user: settings.arguments! as AppUser,
      ),
      _ => const LoginPage(),
    };
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }

  /// Con permisos de administración: panel de admin (sus secciones dependen
  /// de cada permiso). Solo con "gestionar mis hijos": Mi familia.
  ///
  /// Si la API no informa permisos (versión sin roles/permisos en `/me`),
  /// se usa Mi familia, que es la experiencia base de todo usuario.
  static Widget _homeFor(AppUser user) =>
      user.permissions.isEmpty ||
          (!user.isAdmin && user.can(Permissions.ownDependents))
      ? FamilyPage(user: user)
      : AdminHomePage(user: user);
}
