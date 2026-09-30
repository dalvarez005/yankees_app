import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/app_user.dart';
import '../../auth/presentation/widgets/auth_field.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../data/category_repository.dart';

/// CRUD de categorías (requiere `categorias.gestionar`). Desactivar no borra,
/// y la API no lo permite mientras algún hijo la tenga asignada.
class CategoriesAdminPage extends StatefulWidget {
  const CategoriesAdminPage({super.key, required this.user});

  final AppUser user;

  @override
  State<CategoriesAdminPage> createState() => _CategoriesAdminPageState();
}

class _CategoriesAdminPageState extends State<CategoriesAdminPage> {
  List<Category>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await CategoryRepository.instance.list();
      if (mounted) setState(() => _items = items);
    } on CategoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit([Category? category]) async {
    final saved = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CategoryForm(category: category),
    );
    if (saved == null || !mounted) return;
    showAppMessage(
      context,
      category == null
          ? 'Categoría "${saved.name}" creada.'
          : 'Categoría "${saved.name}" actualizada.',
    );
    await _load();
  }

  Future<void> _reactivate(Category c) async {
    try {
      await CategoryRepository.instance.reactivate(c.id);
      if (!mounted) return;
      showAppMessage(context, '"${c.name}" está activa de nuevo.');
      await _load();
    } on CategoryException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    }
  }

  Future<void> _deactivate(Category c) async {
    final ok = await confirmAction(
      context,
      title: '¿Desactivar "${c.name}"?',
      message:
          'Ya no se podrá elegir para hijos. Solo se puede desactivar si '
          'ningún hijo la tiene asignada.',
      confirmLabel: 'Desactivar',
    );
    if (!ok) return;
    try {
      await CategoryRepository.instance.deactivate(c.id);
      if (!mounted) return;
      showAppMessage(context, '"${c.name}" desactivada.');
      await _load();
    } on CategoryException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.categoriesManage)) {
      return const NoAccessView();
    }
    final items = _items;
    final active = [...?items?.where((c) => c.active)];
    final inactive = [...?items?.where((c) => !c.active)];
    return Scaffold(
      appBar: pageAppBar(context, 'Categorías'),
      floatingActionButton: items == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _edit,
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva categoría'),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: AsyncListView(
          loading: items == null,
          error: _error,
          onRetry: _load,
          empty: EmptyState(
            icon: Icons.sports_baseball_outlined,
            title: 'Aún no hay categorías',
            message: 'Crea la primera para que los padres la elijan.',
            actionLabel: 'Nueva categoría',
            onAction: _edit,
          ),
          children: [
            if (active.isNotEmpty) ListHeader('Activas', count: active.length),
            for (final c in active)
              _CategoryTile(
                category: c,
                onEdit: () => _edit(c),
                onDeactivate: () => _deactivate(c),
              ),
            if (inactive.isNotEmpty) ...[
              const SizedBox(height: 10),
              ListHeader('Inactivas', count: inactive.length),
              for (final c in inactive)
                _CategoryTile(category: c, onReactivate: () => _reactivate(c)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    this.onEdit,
    this.onDeactivate,
    this.onReactivate,
  });

  final Category category;

  /// null en las inactivas: la API no las edita.
  final VoidCallback? onEdit;
  final VoidCallback? onDeactivate;
  final VoidCallback? onReactivate;

  @override
  Widget build(BuildContext context) {
    final c = category;
    return ListCard(
      onTap: onEdit,
      dimmed: !c.active,
      leading: AppAvatar(
        seed: c.name,
        icon: Icons.sports_baseball_outlined,
        muted: !c.active,
      ),
      title: c.name,
      subtitle: c.active
          ? 'Disponible para inscribir hijos'
          : 'No se ofrece a hijos nuevos',
      trailing: onEdit == null
          ? Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: onReactivate,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Reactivar'),
              ),
            )
          : PopupMenuButton<String>(
              tooltip: 'Opciones',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppColors.textMuted,
              ),
              onSelected: (v) => v == 'edit' ? onEdit!() : onDeactivate!(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(
                  value: 'deactivate',
                  child: Text(
                    'Desactivar',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({this.category});
  final Category? category;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.name);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = CategoryRepository.instance;
      final c = widget.category;
      final saved = c == null
          ? await repo.create(_name.text)
          : await repo.rename(c.id, _name.text);
      if (mounted) Navigator.of(context).pop(saved);
    } on CategoryException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.category == null ? 'Nueva categoría' : 'Editar categoría',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            AuthField(
              label: 'Nombre',
              hint: 'Ej. Preinfantil',
              icon: Icons.sports_baseball_outlined,
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'El nombre es obligatorio';
                if (t.length > 100) return 'Máximo 100 caracteres';
                return null;
              },
            ),
            const SizedBox(height: 24),
            LoadingButton(label: 'Guardar', loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
