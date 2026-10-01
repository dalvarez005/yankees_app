import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/app_user.dart';
import '../../auth/presentation/widgets/auth_field.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../data/admin_repository.dart';
import '../../../core/widgets/form_ready.dart';

/// Roles y sus permisos: solo SUPER_ADMIN (la API lo valida por rol).
class RolesPage extends StatefulWidget {
  const RolesPage({super.key, required this.user});

  final AppUser user;

  @override
  State<RolesPage> createState() => _RolesPageState();
}

class _RolesPageState extends State<RolesPage> {
  List<Role>? _roles;
  List<PermissionInfo> _catalog = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repo = AdminRepository.instance;
      final catalogFuture = repo.permissions();
      final roles = await repo.roles();
      final catalog = await catalogFuture;
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _catalog = catalog;
      });
    } on AdminException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open([Role? role]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RoleFormPage(role: role, catalog: _catalog),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Role role) async {
    final ok = await confirmAction(
      context,
      title: '¿Eliminar el rol "${role.name}"?',
      message: 'Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
    );
    if (!ok) return;
    try {
      await AdminRepository.instance.deleteRole(role.id);
      if (!mounted) return;
      showAppMessage(context, 'Rol "${role.name}" eliminado.');
      await _load();
    } on AdminException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.isSuperAdmin) return const NoAccessView();
    final roles = _roles;
    return Scaffold(
      appBar: pageAppBar(context, 'Roles y permisos'),
      floatingActionButton: roles == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _open,
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo rol'),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: AsyncListView(
          loading: roles == null,
          error: _error,
          onRetry: _load,
          header: roles == null || roles.isEmpty
              ? null
              : ListHeader('Roles', count: roles.length),
          empty: EmptyState(
            icon: Icons.shield_outlined,
            title: 'Aún no hay roles',
            message: 'Crea uno y elige qué puede hacer.',
            actionLabel: 'Nuevo rol',
            onAction: _open,
          ),
          children: [
            for (final r in roles ?? const <Role>[])
              _RoleTile(
                role: r,
                totalPermissions: _catalog.length,
                onTap: () => _open(r),
                onDelete: r.isSystem ? null : () => _delete(r),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.role,
    required this.totalPermissions,
    required this.onTap,
    this.onDelete,
  });

  final Role role;
  final int totalPermissions;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final count = role.isSuperAdmin
        ? totalPermissions
        : role.permissions.length;
    final share = totalPermissions == 0 ? 0.0 : count / totalPermissions;
    final users = role.userCount == 1
        ? '1 usuario'
        : '${role.userCount} usuarios';
    final color = role.isSuperAdmin ? AppColors.navy : avatarColor(role.name);
    return ListCard(
      onTap: onTap,
      leading: AppAvatar(
        seed: role.name,
        icon: role.isSuperAdmin
            ? Icons.workspace_premium_rounded
            : Icons.shield_outlined,
      ),
      title: roleLabel(role.name),
      subtitle: role.isSuperAdmin
          ? 'Todos los permisos · $users'
          : '$count de $totalPermissions permisos · $users',
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 5,
              color: color,
              backgroundColor: AppColors.border,
            ),
          ),
          if (role.isSystem) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                const Pill('Sistema', icon: Icons.lock_outline_rounded),
                if (role.isDefault)
                  const Pill('Por defecto', tone: PillTone.brand),
              ],
            ),
          ],
        ],
      ),
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: 'Eliminar rol',
              icon: const Icon(Icons.delete_outline_rounded),
              color: AppColors.error,
              onPressed: onDelete,
            ),
    );
  }
}

/// Crear o editar un rol. Devuelve true si guardó.
class RoleFormPage extends StatefulWidget {
  const RoleFormPage({super.key, this.role, required this.catalog});

  final Role? role;
  final List<PermissionInfo> catalog;

  @override
  State<RoleFormPage> createState() => _RoleFormPageState();
}

class _RoleFormPageState extends State<RoleFormPage> with FormReady {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.role?.name);
  late final Set<String> _selected = {...?widget.role?.permissions};
  bool _saving = false;

  Role? get _role => widget.role;
  bool get _readOnlyPermissions => _role?.isSuperAdmin ?? false;

  static String? _nameError(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'El nombre es obligatorio';
    if (t.length > 60) return 'Máximo 60 caracteres';
    return null;
  }

  @override
  void initState() {
    super.initState();
    watchFields([_name]);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = AdminRepository.instance;
      final role = _role;
      if (role == null) {
        await repo.createRole(name: _name.text, permissions: _selected);
      } else {
        final renamed = !role.isSystem && _name.text.trim() != role.name;
        await repo.updateRole(
          role.id,
          name: renamed ? _name.text : null,
          permissions: _readOnlyPermissions ? null : _selected,
        );
      }
      if (!mounted) return;
      showAppMessage(context, 'Rol guardado.');
      Navigator.of(context).pop(true);
    } on AdminException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final byModule = <String, List<PermissionInfo>>{};
    for (final p in widget.catalog) {
      (byModule[p.module] ??= []).add(p);
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Atrás',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_role == null ? 'Nuevo rol' : roleLabel(_role!.name)),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (_role?.isSystem ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _readOnlyPermissions
                      ? 'Rol del sistema: siempre tiene todos los permisos '
                            'y no se puede modificar.'
                      : 'Rol del sistema: su nombre no cambia, pero puedes '
                            'ajustar sus permisos.',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            AuthField(
              label: 'Nombre',
              hint: 'Ej. Secretaría',
              icon: Icons.badge_outlined,
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              enabled: !(_role?.isSystem ?? false),
              validator: _nameError,
            ),
            const SizedBox(height: 24),
            Text(
              'Permisos',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            for (final entry in byModule.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text(
                  entry.key.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              for (final p in entry.value)
                CheckboxListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _readOnlyPermissions || _selected.contains(p.code),
                  onChanged: _readOnlyPermissions
                      ? null
                      : (v) => setState(
                          () => v == true
                              ? _selected.add(p.code)
                              : _selected.remove(p.code),
                        ),
                  title: Text(p.name),
                  subtitle: p.description == null
                      ? null
                      : Text(
                          p.description!,
                          style: const TextStyle(fontSize: 12),
                        ),
                ),
            ],
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Guardar',
              loading: _saving,
              onPressed: _nameError(_name.text) == null ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}
