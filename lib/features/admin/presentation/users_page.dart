import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/paging/page_of.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/paged_list.dart';
import '../../auth/data/app_user.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../../billing/presentation/pending_users_page.dart';
import '../data/admin_repository.dart';

/// Usuarios con su rol y estado. Ver requiere `usuarios.ver`; cambiar rol o
/// activar/desactivar, `usuarios.gestionar`.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.user});

  final AppUser user;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Role> _roles = const [];
  String _search = '';
  Map<String, Object?> _filters = const {};

  /// Lo último que devolvió la API para la búsqueda actual. La API no
  /// pagina ni filtra por rol o estado, así que eso se hace aquí.
  List<ManagedUser> _all = const [];

  late final _list = PagedController<ManagedUser>((page, pageSize) async {
    if (page == 1) {
      final users = await AdminRepository.instance.users(search: _search);
      _all = users;
      // Para que el filtro de rol ofrezca los roles que hay.
      if (mounted) setState(() {});
    }
    final role = _filters['role'] as String?;
    final active = _filters['status'] as bool?;
    return pageOf(
      [
        for (final u in _all)
          if ((role == null || u.roleName == role) &&
              (active == null || u.active == active))
            u,
      ],
      page,
      pageSize,
    );
  });

  bool get _canManage => widget.user.can(Permissions.usersManage);

  /// Roles presentes entre los usuarios cargados.
  List<FilterChoice> get _roleChoices {
    final names = {for (final u in _all) ?u.roleName}.toList()..sort();
    return [for (final n in names) FilterChoice(n, roleLabel(n))];
  }

  @override
  void initState() {
    super.initState();
    _list.refresh();
    if (_canManage) _loadRoles();
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await AdminRepository.instance.roles();
      if (mounted) setState(() => _roles = roles);
    } on AdminException {
      // Sin la lista de roles solo se podrá activar/desactivar.
    }
  }

  Future<void> _open(ManagedUser u) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _UserSheet(
        user: u,
        roles: _roles,
        canManage: _canManage,
        canValidate: widget.user.can(Permissions.usersValidate),
        isSelf: u.id == widget.user.id,
      ),
    );
    if (changed == true) await _list.refresh(keepItems: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.usersView)) return const NoAccessView();
    final roleChoices = _roleChoices;
    final filtered = _search.isNotEmpty || _filters.isNotEmpty;
    return Scaffold(
      appBar: pageAppBar(context, 'Usuarios'),
      body: Column(
        children: [
          FilterBar(
            searchHint: 'Buscar por nombre o correo',
            filters: [
              if (roleChoices.length > 1)
                FilterSpec(
                  key: 'role',
                  title: 'Rol',
                  icon: Icons.badge_outlined,
                  choices: roleChoices,
                ),
              const FilterSpec(
                key: 'status',
                title: 'Estado',
                icon: Icons.toggle_on_outlined,
                choices: [
                  FilterChoice(true, 'Activos'),
                  FilterChoice(false, 'Inactivos'),
                ],
              ),
            ],
            values: _filters,
            search: _search,
            onChanged: (search, values) {
              setState(() {
                _search = search;
                _filters = values;
              });
              _list.refresh();
            },
          ),
          Expanded(
            child: PagedListView<ManagedUser>(
              controller: _list,
              empty: EmptyState(
                icon: Icons.person_search_rounded,
                title: 'Sin resultados',
                message: filtered
                    ? 'Ninguna cuenta coincide con la búsqueda o los filtros.'
                    : 'Todavía no hay cuentas registradas.',
              ),
              itemBuilder: (context, u) => _UserTile(
                user: u,
                isSelf: u.id == widget.user.id,
                onTap: () => _open(u),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _initials(ManagedUser u) => (u.name.isEmpty ? u.email : u.name)
    .split(RegExp(r'[\s.@_-]+'))
    .where((p) => p.isNotEmpty)
    .take(2)
    .map((p) => p[0].toUpperCase())
    .join();

/// El rol como pill: el super admin destacado.
Widget _rolePill(String? roleName) => Pill(
  roleLabel(roleName ?? '—'),
  tone: PillTone.brand,
  filled: roleName?.toUpperCase() == 'SUPER_ADMIN',
);

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.isSelf,
    required this.onTap,
  });

  final ManagedUser user;
  final bool isSelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final u = user;
    return ListCard(
      onTap: onTap,
      dimmed: !u.active,
      leading: AppAvatar(
        seed: u.email,
        initials: _initials(u),
        muted: !u.active,
      ),
      title: [u.name.isEmpty ? u.email : u.name, if (isSelf) '(tú)'].join(' '),
      subtitle: u.email,
      footer: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _rolePill(u.roleName),
          if (!u.active)
            const Pill(
              'Inactivo',
              tone: PillTone.danger,
              icon: Icons.block_rounded,
            ),
          if (u.googleLinked) const Pill('Google', icon: Icons.g_mobiledata),
        ],
      ),
    );
  }
}

class _UserSheet extends StatefulWidget {
  const _UserSheet({
    required this.user,
    required this.roles,
    required this.canManage,
    required this.isSelf,
    this.canValidate = false,
  });

  final ManagedUser user;
  final List<Role> roles;
  final bool canManage;
  final bool isSelf;

  /// Ver y editar sus cuotas (`usuarios.validar`).
  final bool canValidate;

  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  late int? _roleId = widget.user.roleId;
  bool _saving = false;

  bool get _editable => widget.canManage && !widget.isSelf;

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() => _saving = true);
    try {
      await action();
      if (!mounted) return;
      showAppMessage(context, message);
      Navigator.of(context).pop(true);
    } on AdminException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive() async {
    final u = widget.user;
    if (u.active) {
      final ok = await confirmAction(
        context,
        title: '¿Desactivar a ${u.name.isEmpty ? u.email : u.name}?',
        message:
            'Se cerrará su sesión y no podrá volver a entrar hasta que lo '
            'reactives.',
        confirmLabel: 'Desactivar',
      );
      if (!ok) return;
    }
    await _run(
      () => AdminRepository.instance.setUserActive(u.id, !u.active),
      u.active ? 'Usuario desactivado.' : 'Usuario reactivado.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final roleChanged = _roleId != null && _roleId != u.roleId;
    // SUPER_ADMIN se define solo por base de datos: no se ofrece.
    final roles = [...widget.roles.where((r) => !r.isSuperAdmin)];
    final protected = u.roleName?.toUpperCase() == 'SUPER_ADMIN';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(
                seed: u.email,
                initials: _initials(u),
                size: 56,
                muted: !u.active,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.name.isEmpty ? u.email : u.name,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      u.email,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _rolePill(u.roleName),
              u.active
                  ? const Pill('Activo', tone: PillTone.success)
                  : const Pill('Inactivo', tone: PillTone.danger),
              if (u.googleLinked)
                const Pill('Cuenta de Google', icon: Icons.g_mobiledata),
            ],
          ),
          const SizedBox(height: 24),
          if (!widget.canManage)
            Text(
              'Rol: ${roleLabel(u.roleName ?? '—')}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            )
          else if (widget.isSelf)
            const Text(
              'No puedes cambiar tu propio rol ni desactivarte. Pídeselo a '
              'otro administrador.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else if (protected)
            const Text(
              'El super admin se define solo desde la base de datos; no se '
              'modifica desde la app.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else ...[
            DropdownButtonFormField<int>(
              initialValue: roles.any((r) => r.id == _roleId) ? _roleId : null,
              decoration: const InputDecoration(
                labelText: 'Rol',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
              ),
              items: [
                for (final r in roles)
                  DropdownMenuItem(value: r.id, child: Text(roleLabel(r.name))),
              ],
              onChanged: _saving ? null : (v) => setState(() => _roleId = v),
            ),
            const SizedBox(height: 16),
            LoadingButton(
              label: 'Guardar rol',
              loading: _saving,
              onPressed: roleChanged
                  ? () => _run(
                      () =>
                          AdminRepository.instance.setUserRole(u.id, _roleId!),
                      'Rol actualizado.',
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving || !_editable ? null : _toggleActive,
              style: TextButton.styleFrom(
                foregroundColor: u.active ? AppColors.error : AppColors.navy,
              ),
              child: Text(
                u.active ? 'Desactivar usuario' : 'Reactivar usuario',
              ),
            ),
          ],
          if (widget.canValidate && u.active) ...[
            const SizedBox(height: 20),
            UserFeesSection(userId: u.id, name: u.name, email: u.email),
          ],
        ],
      ),
    );
  }
}
