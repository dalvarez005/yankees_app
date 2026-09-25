import 'package:flutter/material.dart';

import 'app/app_theme.dart';
import 'app/routes.dart';
import 'features/auth/data/app_user.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/register_page.dart';
import 'features/home/home_page.dart';

void main() {
  runApp(const YankeesApp());
}

class YankeesApp extends StatelessWidget {
  const YankeesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Club Yankees',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: Routes.login,
      onGenerateRoute: (settings) {
        final Widget page = switch (settings.name) {
          Routes.register => const RegisterPage(),
          Routes.home => HomePage(user: settings.arguments! as AppUser),
          _ => const LoginPage(),
        };
        return MaterialPageRoute(builder: (_) => page, settings: settings);
      },
    );
  }
}
