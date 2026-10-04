import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/app_theme.dart';
import 'app/env.dart';
import 'app/home.dart';
import 'app/routes.dart';
import 'core/network/api_client.dart';
import 'core/notifications/local_notifier.dart';
import 'core/notifications/push_messaging.dart';
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
import 'features/admin/data/admin_repository.dart';
import 'features/billing/data/billing_repository.dart';
import 'features/categories/data/category_repository.dart';
import 'features/notifications/data/notification_repository.dart';
import 'features/payments/data/payments_repository.dart';
import 'features/payments/data/settings_repository.dart';
import 'features/profile/data/profile_review_store.dart';
import 'features/profile/presentation/confirm_profile_page.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Poppins viene dentro de la app (assets/fonts): no se descarga.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['google_fonts'], license);
  });
  LocalNotifier.instance = DeviceLocalNotifier();
  // Sin configuración de Firebase en la plataforma queda sin push.
  final push = await FirebasePushMessaging.create();
  if (push != null) PushMessaging.instance = push;

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
    PaymentsRepository.instance = ApiPaymentsRepository(api);
    SettingsRepository.instance = ApiSettingsRepository(api);
    BillingRepository.instance = ApiBillingRepository(api);
    NotificationRepository.instance = ApiNotificationRepository(api);
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
  final review = user != null && ProfileReview.needed(user);
  runApp(YankeesApp(initialUser: user, reviewProfile: review));
}

/// Modo sin API: dos hijos de ejemplo para que se vean cobros y pagos.
Future<void> _seedMockFamily() async {
  final repo = DependentRepository.instance;
  for (final (cui, name, birthDate) in [
    ('3004013889191', 'Sofía', DateTime(2017, 3, 9)),
    ('3004013889192', 'Mateo', DateTime(2019, 6, 21)),
  ]) {
    await repo.add(
      DependentInput(
        cui: cui,
        firstName: name,
        firstLastName: 'Castro',
        birthDate: birthDate,
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
      Routes.home => homeFor(settings.arguments! as AppUser),
      Routes.confirmProfile => ConfirmProfilePage(
        user: settings.arguments! as AppUser,
      ),
      _ => const LoginPage(),
    };
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }
}
