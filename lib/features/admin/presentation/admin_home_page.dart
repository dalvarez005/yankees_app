import 'package:flutter/material.dart';

import '../../../core/layout/responsive.dart';

import '../../../core/widgets/club_logo.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../../core/widgets/app_ui.dart';
import '../../auth/data/app_user.dart';
import '../../categories/presentation/categories_admin_page.dart';
import '../../payments/data/payments_repository.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/pending_users_page.dart';
import '../../notifications/presentation/notifications_page.dart';
import '../../payments/presentation/admin/charges_admin_page.dart';
import '../../payments/presentation/admin/insolvents_page.dart';
import '../../payments/presentation/admin/payment_settings_page.dart';
import '../../payments/presentation/admin/review_payments_page.dart';
import '../../profile/presentation/profile_page.dart';
import 'players_page.dart';
import 'roles_page.dart';
import 'users_page.dart';

/// Inicio para quien tiene permisos de administración: resumen en números y
/// accesos a cada sección. Todo aparece solo si el rol tiene el permiso.
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key, required this.user});

  final AppUser user;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  late AppUser _user = widget.user;

  /// Totales del resumen; null = cargando o sin dato.
  final _stats = <String, int?>{};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  /// Cada total por separado: si uno falla, los demás igual se muestran.
  Future<void> _loadStats() async {
    Future<void> load(String key, Future<int> Function() count) async {
      try {
        final value = await count();
        if (mounted) setState(() => _stats[key] = value);
      } catch (_) {
        if (mounted) setState(() => _stats[key] = null);
      }
    }

    final payments = PaymentsRepository.instance;
    await Future.wait([
      if (_user.can(Permissions.paymentsReview))
        load('reviews', () async => (await payments.reviewQueue()).length),
      if (_user.can(Permissions.usersValidate))
        load(
          'pending',
          () async => (await BillingRepository.instance.pendingUsers()).length,
        ),
      if (_user.can(Permissions.paymentsManage))
        load(
          'insolvent',
          () async => (await payments.solvencyReport()).insolventUsers,
        ),
    ]);
  }

  Future<void> _openProfile() async {
    final updated = await Navigator.of(context).push<AppUser>(
      MaterialPageRoute(builder: (_) => ProfilePage(user: _user)),
    );
    if (updated != null && mounted) setState(() => _user = updated);
  }

  /// Al volver de una sección se refrescan los totales.
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final reviews = _stats['reviews'] ?? 0;
    final pending = _stats['pending'] ?? 0;
    final insolvent = _stats['insolvent'] ?? 0;
    final stats = [
      // Solo lo que espera una acción del administrador.
      if (_user.can(Permissions.paymentsReview))
        _Stat(
          'Pagos por validar',
          _stats['reviews'],
          Icons.fact_check_rounded,
          () => _open(ReviewPaymentsPage(user: _user)),
        ),
      if (_user.can(Permissions.usersValidate))
        _Stat(
          'Usuarios por validar',
          _stats['pending'],
          Icons.how_to_reg_rounded,
          () => _open(PendingUsersPage(user: _user)),
        ),
      if (_user.can(Permissions.paymentsManage))
        _Stat(
          'Insolventes',
          _stats['insolvent'],
          Icons.warning_amber_rounded,
          () => _open(InsolventsPage(user: _user)),
        ),
    ];
    final actions = [
      if (_user.can(Permissions.paymentsReview))
        _Action(
          icon: Icons.fact_check_outlined,
          color: const Color(0xFF15803D),
          title: 'Validar pagos',
          subtitle: reviews > 0
              ? '$reviews ${reviews == 1 ? 'comprobante espera' : 'comprobantes esperan'}'
              : 'Aprueba o rechaza comprobantes',
          badge: _stats['reviews'],
          onTap: () => _open(ReviewPaymentsPage(user: _user)),
        ),
      if (_user.can(Permissions.usersValidate))
        _Action(
          icon: Icons.how_to_reg_outlined,
          color: const Color(0xFF0369A1),
          title: 'Usuarios por validar',
          subtitle: pending > 0
              ? '$pending ${pending == 1 ? 'espera' : 'esperan'} sus cuotas'
              : 'Define inscripción y mensualidad',
          badge: _stats['pending'],
          onTap: () => _open(PendingUsersPage(user: _user)),
        ),
      if (_user.can(Permissions.paymentsManage)) ...[
        _Action(
          icon: Icons.warning_amber_rounded,
          color: AppColors.error,
          title: 'Insolventes',
          subtitle: insolvent > 0
              ? '$insolvent con pagos vencidos'
              : 'Familias con pagos vencidos',
          badge: _stats['insolvent'],
          onTap: () => _open(InsolventsPage(user: _user)),
        ),
        _Action(
          icon: Icons.receipt_long_outlined,
          color: const Color(0xFFBE123C),
          title: 'Cobros',
          subtitle: 'Inscripciones y mensualidades',
          onTap: () => _open(ChargesAdminPage(user: _user)),
        ),
      ],
      if (_user.can(Permissions.usersView))
        _Action(
          icon: Icons.people_alt_outlined,
          color: const Color(0xFF0369A1),
          title: 'Usuarios',
          subtitle: _user.can(Permissions.usersManage)
              ? 'Rol y estado de cada cuenta'
              : 'Consulta cuentas y roles',
          onTap: () => _open(UsersPage(user: _user)),
        ),
      if (_user.isSuperAdmin)
        _Action(
          icon: Icons.admin_panel_settings_outlined,
          color: const Color(0xFF6D28D9),
          title: 'Roles y permisos',
          subtitle: 'Qué puede hacer cada rol',
          onTap: () => _open(RolesPage(user: _user)),
        ),
      if (_user.can(Permissions.categoriesManage))
        _Action(
          icon: Icons.sports_baseball_outlined,
          color: const Color(0xFFB45309),
          title: 'Categorías',
          subtitle: 'Moscos, Infantil, Juvenil…',
          onTap: () => _open(CategoriesAdminPage(user: _user)),
        ),
      if (_user.can(Permissions.playersView))
        _Action(
          icon: Icons.groups_rounded,
          color: const Color(0xFF0369A1),
          title: 'Jugadores',
          subtitle: 'Todos los hijos por categoría',
          onTap: () => _open(PlayersPage(user: _user)),
        ),
      if (_user.can(Permissions.settingsManage))
        _Action(
          icon: Icons.tune_rounded,
          color: const Color(0xFF0F766E),
          title: 'Configuración',
          subtitle: 'Cuotas, día límite y WhatsApp',
          onTap: () => _open(PaymentSettingsPage(user: _user)),
        ),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadStats,
        color: AppColors.navy,
        edgeOffset: 80,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _Header(
              user: _user,
              stats: stats,
              onProfile: _openProfile,
              onNotificationsChanged: _loadStats,
            ),
            Padding(
              padding: Responsive.centered(
                context,
                const EdgeInsets.fromLTRB(20, 4, 20, 32),
                maxWidth: Responsive.dashboardMaxWidth,
              ),
              child: actions.isEmpty
                  ? const EmptyState(
                      icon: Icons.lock_outline_rounded,
                      title: 'Sin permisos todavía',
                      message:
                          'Tu rol aún no tiene permisos asignados. Pide '
                          'acceso a un administrador.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ListHeader('Accesos'),
                        GridView(
                          shrinkWrap: true,
                          // Sin el padding del área segura (dejaba un hueco).
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                // 2 en teléfono; más columnas en tablet y PC.
                                crossAxisCount: Responsive.columns(
                                  MediaQuery.sizeOf(context).width
                                      .clamp(0, Responsive.dashboardMaxWidth)
                                      .toDouble(),
                                ),
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                // Alto fijo: con más columnas no se estiran.
                                mainAxisExtent: 160,
                              ),
                          children: actions,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.stats,
    required this.onProfile,
    required this.onNotificationsChanged,
  });

  final AppUser user;
  final List<_Stat> stats;
  final VoidCallback onProfile;
  final VoidCallback onNotificationsChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return BrandHeader(
      maxWidth: Responsive.dashboardMaxWidth,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ClubLogo(size: 40),
                  const SizedBox(width: 10),
                  Text(
                    'CLUB YANKEES',
                    style: text.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  NotificationBell(
                    user: user,
                    onChanged: onNotificationsChanged,
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Mi perfil',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onProfile,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.navy,
                          child: Text(
                            user.initials,
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
              const SizedBox(height: 26),
              Text(
                'Hola, ${user.firstName.isEmpty ? user.displayName : user.firstName}',
                style: text.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_user_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          roleLabel(user.roleName),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Panel de administración',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 22),
                // Hasta 3 ocupan el ancho; con más se desliza de lado.
                // IntrinsicHeight + stretch: todas del alto de la más alta,
                // aunque una etiqueta ocupe dos líneas y otra una.
                if (stats.length <= 3)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, s) in stats.indexed) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: _StatTile(stat: s)),
                        ],
                      ],
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, s) in stats.indexed) ...[
                            if (i > 0) const SizedBox(width: 10),
                            SizedBox(width: 104, child: _StatTile(stat: s)),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon, this.onTap);
  final String label;
  final int? value;
  final IconData icon;

  /// Lleva a la pantalla donde se atiende ese pendiente.
  final VoidCallback onTap;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: stat.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                stat.icon,
                color: Colors.white.withValues(alpha: 0.7),
                size: 18,
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  stat.value?.toString() ?? '—',
                  key: ValueKey(stat.value),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                stat.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Pendientes que requieren atención (se muestra si es mayor a 0).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const Spacer(),
                  if ((badge ?? 0) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 18,
                      color: AppColors.textMuted.withValues(alpha: 0.7),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
