import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/app_user.dart';
import '../../auth/presentation/widgets/loading_button.dart';
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
  final _search = TextEditingController();
  List<ManagedUser>? _users;
  List<Role> _roles = const [];
  String? _error;

  bool get _canManage => widget.user.can(Permissions.usersManage);

  @override
  void initState() {
    super.initState();
    _load();
    if (_canManage) _loadRoles();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final users = await AdminRepository.instance.users(search: _search.text);
      if (mounted) setState(() => _users = users);
    } on AdminException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
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
        isSelf: u.id == widget.user.id,
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.usersView)) return const NoAccessView();
    final users = _users;
    return Scaffold(
      appBar: pageAppBar(context, 'Usuarios'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o correo',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: 'Limpiar',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _search.clear();
                    _load();
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: AsyncListView(
                loading: users == null,
                error: _error,
                onRetry: _load,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                header: users == null || users.isEmpty
                    ? null
                    : ListHeader(
                        users.length == 1 ? 'Cuenta' : 'Cuentas',
                        count: users.length,
                      ),
                empty: EmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'Sin resultados',
                  message: _search.text.trim().isEmpty
                      ? 'Todavía no hay cuentas registradas.'
                      : 'Ninguna cuenta coincide con "${_search.text.trim()}".',
                ),
                children: [
                  for (final u in users ?? const <ManagedUser>[])
                    _UserTile(
                      user: u,
                      isSelf: u.id == widget.user.id,
                      onTap: () => _open(u),
                    ),
                ],
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
  });

  final ManagedUser user;
  final List<Role> roles;
  final bool canManage;
  final bool isSelf;

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
          else ...[
            DropdownButtonFormField<int>(
              initialValue: widget.roles.any((r) => r.id == _roleId)
                  ? _roleId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Rol',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
              ),
              items: [
                for (final r in widget.roles)
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
        ],
      ),
    );
  }
}
