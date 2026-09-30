import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Atrás',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Categorías'),
      ),
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
        child: switch ((items, _error)) {
          (null, final String error) => ListView(
            padding: const EdgeInsets.all(32),
            children: [
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _load,
                  child: const Text('Reintentar'),
                ),
              ),
            ],
          ),
          (null, _) => const Center(
            child: CircularProgressIndicator(color: AppColors.navy),
          ),
          (final List<Category> list, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Aún no hay categorías. Crea la primera.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              for (final c in list)
                _CategoryTile(
                  category: c,
                  onEdit: c.active ? () => _edit(c) : null,
                  onDeactivate: c.active ? () => _deactivate(c) : null,
                ),
            ],
          ),
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onEdit,
    required this.onDeactivate,
  });

  final Category category;

  /// null en las inactivas: la API no las edita.
  final VoidCallback? onEdit;
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final c = category;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: c.active ? AppColors.surface : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onEdit,
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        title: Row(
          children: [
            Flexible(
              child: Text(
                c.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: c.active ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ),
            if (!c.active) ...[
              const SizedBox(width: 8),
              const _Badge('Inactiva'),
            ],
          ],
        ),
        trailing: onEdit == null
            ? null
            : PopupMenuButton<String>(
                tooltip: 'Opciones',
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
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.textMuted.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
    ),
  );
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
