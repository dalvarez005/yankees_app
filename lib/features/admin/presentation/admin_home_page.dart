import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../auth/data/app_user.dart';
import '../../categories/presentation/categories_admin_page.dart';
import '../../family/presentation/family_page.dart';
import '../../profile/presentation/profile_page.dart';
import 'roles_page.dart';
import 'users_page.dart';

/// Inicio para quien tiene permisos de administración. Cada sección aparece
/// solo si el rol tiene el permiso correspondiente.
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key, required this.user});

  final AppUser user;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  late AppUser _user = widget.user;

  Future<void> _openProfile() async {
    final updated = await Navigator.of(context).push<AppUser>(
      MaterialPageRoute(builder: (_) => ProfilePage(user: _user)),
    );
    if (updated != null && mounted) setState(() => _user = updated);
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final sections = [
      if (_user.can(Permissions.usersView))
        _Section(
          icon: Icons.people_alt_outlined,
          title: 'Usuarios',
          subtitle: _user.can(Permissions.usersManage)
              ? 'Busca usuarios, cambia su rol o desactívalos.'
              : 'Consulta los usuarios y su rol.',
          onTap: () => _open(UsersPage(user: _user)),
        ),
      if (_user.can(Permissions.rolesManage))
        _Section(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Roles y permisos',
          subtitle: 'Crea roles y elige qué puede hacer cada uno.',
          onTap: () => _open(RolesPage(user: _user)),
        ),
      if (_user.can(Permissions.categoriesManage))
        _Section(
          icon: Icons.sports_baseball_outlined,
          title: 'Categorías',
          subtitle: 'Moscos, Preinfantil, Infantil… agrega o edita.',
          onTap: () => _open(CategoriesAdminPage(user: _user)),
        ),
      if (_user.can(Permissions.ownDependents))
        _Section(
          icon: Icons.family_restroom_rounded,
          title: 'Mi familia',
          subtitle: 'Tus hijos inscritos en el club.',
          onTap: () => _open(FamilyPage(user: _user, embedded: true)),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Administración'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: 'Mi perfil',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _openProfile,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.navy,
                  child: Text(
                    _user.initials,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'Hola, ${_user.displayName}',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(roleLabel(_user.roleName)),
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
              backgroundColor: AppColors.navy.withValues(alpha: 0.08),
              labelStyle: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (sections.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Tu rol aún no tiene permisos asignados. Pide acceso a un '
                'administrador.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ...sections,
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.navy.withValues(alpha: 0.08),
          foregroundColor: AppColors.navy,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
