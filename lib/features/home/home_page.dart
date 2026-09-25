import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/routes.dart';
import '../auth/data/app_user.dart';
import '../auth/data/auth_repository.dart';

/// Pantalla temporal: confirma el login y el rol. Aquí irán los paneles
/// de padre (hijos, saldo, comprobantes) y de admin.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text(user.isAdmin ? 'Panel de administración' : 'Mi familia'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await AuthRepository.instance.signOut();
              if (!context.mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil(Routes.login, (_) => false);
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                user.isAdmin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.family_restroom_rounded,
                size: 64,
                color: AppColors.navy,
              ),
              const SizedBox(height: 16),
              Text(
                'Hola, ${user.fullName}',
                style: text.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                user.isAdmin ? 'Rol: administrador' : 'Rol: padre / tutor',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
