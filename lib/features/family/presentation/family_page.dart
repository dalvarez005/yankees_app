import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../auth/data/app_user.dart';
import '../../profile/presentation/profile_page.dart';
import '../data/dependent.dart';
import '../data/dependent_repository.dart';
import 'dependent_form_page.dart';

/// Inicio del padre/madre/tutor: sus hijos registrados.
class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key, required this.user});

  final AppUser user;

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  late AppUser _user = widget.user;
  List<Dependent>? _dependents;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await DependentRepository.instance.list();
      if (mounted) setState(() => _dependents = items);
    } on DependentException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openForm([Dependent? dependent]) async {
    final saved = await Navigator.of(context).push<Dependent>(
      MaterialPageRoute(
        builder: (_) => DependentFormPage(dependent: dependent),
      ),
    );
    if (saved == null || !mounted) return;
    _showMessage(
      dependent == null
          ? '${saved.firstName} fue agregado a tu familia.'
          : 'Datos de ${saved.firstName} actualizados.',
    );
    await _load();
  }

  Future<void> _confirmRemove(Dependent dependent) async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text('¿Quitar a ${dependent.firstName}?'),
        content: const Text(
          'Dejará de aparecer en tu familia. Podrás volver a agregarlo '
          'con su CUI.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DependentRepository.instance.remove(dependent.id);
      _showMessage('${dependent.firstName} fue quitado de tu familia.');
      await _load();
    } on DependentException catch (e) {
      _showMessage(e.message, error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? AppColors.error : AppColors.navy,
        ),
      );
  }

  Future<void> _openProfile() async {
    final updated = await Navigator.of(context).push<AppUser>(
      MaterialPageRoute(builder: (_) => ProfilePage(user: _user)),
    );
    if (updated != null && mounted) setState(() => _user = updated);
  }

  @override
  Widget build(BuildContext context) {
    final dependents = _dependents;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Mi familia'),
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
      floatingActionButton: (dependents?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Agregar hijo'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: _body(dependents),
      ),
    );
  }

  Widget _body(List<Dependent>? dependents) {
    if (_error != null && dependents == null) {
      return _Scrollable(
        child: _StatusMessage(
          icon: Icons.cloud_off_rounded,
          title: 'No pudimos cargar tu familia',
          message: _error!,
          actionLabel: 'Reintentar',
          actionIcon: Icons.refresh_rounded,
          onAction: _load,
        ),
      );
    }
    if (dependents == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.navy),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Text(
          'Hola, ${_user.displayName}',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          dependents.isEmpty
              ? 'Aquí verás a tus hijos inscritos en el club.'
              : dependents.length == 1
              ? 'Tienes 1 hijo registrado.'
              : 'Tienes ${dependents.length} hijos registrados.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        if (dependents.isEmpty)
          _StatusMessage(
            icon: Icons.family_restroom_rounded,
            title: 'Aún no registras a tus hijos',
            message: 'Agrégalos con su CUI para ver sus pagos e inscripciones.',
            actionLabel: 'Agregar hijo',
            onAction: _openForm,
          )
        else
          for (final d in dependents)
            _DependentCard(
              dependent: d,
              onEdit: () => _openForm(d),
              onRemove: () => _confirmRemove(d),
            ),
      ],
    );
  }
}

class _DependentCard extends StatelessWidget {
  const _DependentCard({
    required this.dependent,
    required this.onEdit,
    required this.onRemove,
  });

  final Dependent dependent;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

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
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                child: Text(
                  dependent.initials,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dependent.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'CUI ${dependent.formattedCui}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Chip(categoryName(dependent.categoryId)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.textMuted,
                ),
                onSelected: (v) => v == 'edit' ? onEdit() : onRemove(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(
                      'Quitar',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon = Icons.add_rounded,
  });

  final IconData icon;
  final IconData actionIcon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, size: 64, color: AppColors.navy.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAction,
            icon: Icon(actionIcon),
            label: Text(actionLabel),
            style: FilledButton.styleFrom(minimumSize: const Size(200, 50)),
          ),
        ],
      ),
    );
  }
}

/// Para que el "deslizar para actualizar" funcione en los estados vacíos.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(20),
    children: [child],
  );
}
