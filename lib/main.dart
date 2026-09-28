import 'package:flutter/material.dart';

import 'app/app_colors.dart';
import 'app/app_theme.dart';
import 'app/env.dart';
import 'app/routes.dart';
import 'core/network/api_client.dart';
import 'core/session/session_manager.dart';
import 'core/session/session_store.dart';
import 'features/auth/data/api_auth_repository.dart';
import 'features/auth/data/app_user.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/google_id_token_provider.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/register_page.dart';
import 'features/home/home_page.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

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
  }

  // Si quedó una sesión guardada, se entra directo sin pedir login.
  final user = await AuthRepository.instance.restoreSession();
  runApp(YankeesApp(initialUser: user));
}

/// La API rechazó el refresh token: se vuelve al login avisando.
void _onSessionExpired() {
  _navigatorKey.currentState?.pushNamedAndRemoveUntil(
    Routes.login,
    (_) => false,
  );
  _messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Tu sesión expiró. Inicia sesión de nuevo.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
      ),
    );
}

class YankeesApp extends StatelessWidget {
  const YankeesApp({super.key, this.initialUser});

  /// Usuario de una sesión restaurada; null abre el login.
  final AppUser? initialUser;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Club Yankees',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      onGenerateInitialRoutes: (_) => [
        initialUser == null
            ? _route(const RouteSettings(name: Routes.login))
            : _route(RouteSettings(name: Routes.home, arguments: initialUser)),
      ],
      onGenerateRoute: _route,
    );
  }

  static Route<void> _route(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      Routes.register => const RegisterPage(),
      Routes.home => HomePage(user: settings.arguments! as AppUser),
      _ => const LoginPage(),
    };
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }
}
