import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/app_user.dart';
import '../../auth/presentation/widgets/auth_field.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../data/admin_repository.dart';

/// Roles y sus permisos (requiere `roles.gestionar`).
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
    if (!widget.user.can(Permissions.rolesManage)) return const NoAccessView();
    final roles = _roles;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Atrás',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Roles y permisos'),
      ),
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
        child: roles == null
            ? ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  if (_error == null)
                    const Center(
                      child: CircularProgressIndicator(color: AppColors.navy),
                    )
                  else ...[
                    Text(_error!, textAlign: TextAlign.center),
                    Center(
                      child: TextButton(
                        onPressed: _load,
                        child: const Text('Reintentar'),
                      ),
                    ),
                  ],
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  for (final r in roles)
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
    final perms = role.isSuperAdmin
        ? 'Todos los permisos'
        : '${role.permissions.length} de $totalPermissions permisos';
    final users = role.userCount == 1
        ? '1 usuario'
        : '${role.userCount} usuarios';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        title: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              roleLabel(role.name),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (role.isSystem) const _Tag('Sistema'),
            if (role.isDefault) const _Tag('Por defecto'),
          ],
        ),
        subtitle: Text(
          '$perms · $users',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        trailing: onDelete == null
            ? const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              )
            : IconButton(
                tooltip: 'Eliminar rol',
                icon: const Icon(Icons.delete_outline_rounded),
                color: AppColors.error,
                onPressed: onDelete,
              ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.navy.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.navy,
      ),
    ),
  );
}

/// Crear o editar un rol. Devuelve true si guardó.
class RoleFormPage extends StatefulWidget {
  const RoleFormPage({super.key, this.role, required this.catalog});

  final Role? role;
  final List<PermissionInfo> catalog;

  @override
  State<RoleFormPage> createState() => _RoleFormPageState();
}

class _RoleFormPageState extends State<RoleFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.role?.name);
  late final Set<String> _selected = {...?widget.role?.permissions};
  bool _saving = false;

  Role? get _role => widget.role;
  bool get _readOnlyPermissions => _role?.isSuperAdmin ?? false;

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
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'El nombre es obligatorio';
                if (t.length > 60) return 'Máximo 60 caracteres';
                return null;
              },
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
            LoadingButton(label: 'Guardar', loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
