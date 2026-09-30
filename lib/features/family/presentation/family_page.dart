import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/app_ui.dart';
import '../../auth/data/app_user.dart';
import '../../profile/presentation/profile_page.dart';
import '../../categories/data/category_repository.dart';
import '../data/dependent.dart';
import '../data/dependent_repository.dart';
import 'dependent_form_page.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/format/formats.dart';
import '../../payments/data/payment_models.dart';
import '../../payments/data/payments_repository.dart';
import '../../payments/presentation/charge_detail_page.dart';
import '../../payments/presentation/charge_widgets.dart';
import '../../payments/presentation/solvency_page.dart';

/// Inicio del padre/madre/tutor: sus hijos registrados.
class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key, required this.user, this.embedded = false});

  final AppUser user;

  /// Abierta desde el panel de administración: botón atrás en vez del perfil.
  final bool embedded;

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  late AppUser _user = widget.user;
  List<Dependent>? _dependents;
  List<Category> _categories = const [];
  String? _error;

  /// null mientras carga o si falló (los hijos se muestran igual).
  Balance? _balance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // En paralelo, pero esperando cada uno para conservar el tipo de error.
      final categoriesFuture = _loadCategories();
      final balanceFuture = _loadBalance();
      final items = await DependentRepository.instance.list();
      final categories = await categoriesFuture;
      if (mounted) {
        setState(() {
          _dependents = [
            for (final d in items) _resolveCategory(d, categories),
          ];
          _categories = categories;
        });
      }
      await balanceFuture;
    } on DependentException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Si falla, la pantalla funciona igual sin el saldo.
  Future<void> _loadBalance() async {
    try {
      final charges = await PaymentsRepository.instance.myCharges();
      if (mounted) setState(() => _balance = Balance(charges));
    } on PaymentsException {
      // Sin saldo: se oculta la sección de pagos.
    }
  }

  Future<void> _openCharge(Charge c) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ChargeDetailPage(charge: c)),
    );
    if (changed == true) await _loadBalance();
  }

  Future<void> _openPayments() async {
    final b = _balance;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => b != null && b.solvent
            ? const SolvencyPage()
            : const MyPaymentsPage(),
      ),
    );
    await _loadBalance();
  }

  /// Lo más urgente primero: rechazados, vencidos, por pagar, en revisión.
  List<Charge> get _urgent {
    int rank(Charge c) => switch (c.status) {
      ChargeStatus.rejected => 0,
      ChargeStatus.pending when c.overdue => 1,
      ChargeStatus.pending => 2,
      _ => 3,
    };
    return [...?_balance?.open]..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return (a.dueDate ?? a.createdAt).compareTo(b.dueDate ?? b.createdAt);
    });
  }

  /// Si falla, se siguen mostrando los hijos (sin nombre de categoría).
  Future<List<Category>> _loadCategories() async {
    try {
      return await CategoryRepository.instance.list();
    } on CategoryException {
      return _categories;
    }
  }

  /// La lista de la API trae el nombre de la categoría pero no su id, que
  /// el formulario necesita para editar.
  static Dependent _resolveCategory(Dependent d, List<Category> categories) {
    if (d.categoryId != 0 || d.categoryName == null) return d;
    final name = d.categoryName!.toLowerCase();
    final match = categories.where((c) => c.name.toLowerCase() == name);
    return match.isEmpty ? d : d.withCategoryId(match.first.id);
  }

  String _categoryName(Dependent d) =>
      d.categoryName ??
      _categories
          .where((c) => c.id == d.categoryId)
          .map((c) => c.name)
          .firstOrNull ??
      'Sin categoría';

  Future<void> _openForm([Dependent? dependent]) async {
    final saved = await Navigator.of(context).push<Dependent>(
      MaterialPageRoute(
        builder: (_) =>
            DependentFormPage(dependent: dependent, categories: _categories),
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
    showAppMessage(context, message, error: error);
  }

  Future<void> _openProfile() async {
    final updated = await Navigator.of(context).push<AppUser>(
      MaterialPageRoute(builder: (_) => ProfilePage(user: _user)),
    );
    if (updated != null && mounted) setState(() => _user = updated);
  }

  String get _summary {
    final n = _dependents?.length ?? 0;
    if (_dependents == null) return 'Cargando tu familia…';
    if (n == 0) return 'Aquí verás a tus hijos inscritos en el club.';
    return n == 1
        ? 'Tienes 1 hijo registrado.'
        : 'Tienes $n hijos registrados.';
  }

  @override
  Widget build(BuildContext context) {
    final dependents = _dependents;
    final balance = _balance;
    final urgent = _urgent;
    final list = [
      for (final d in dependents ?? const <Dependent>[])
        _DependentCard(
          dependent: d,
          categoryName: _categoryName(d),
          owed: balance?.owedBy(d.id),
          onEdit: () => _openForm(d),
          onRemove: () => _confirmRemove(d),
        ),
    ];
    final payments = [
      if (widget.embedded && balance != null) ...[
        _EmbeddedBalance(balance: balance, onTap: _openPayments),
        const SizedBox(height: 10),
      ],
      if (urgent.isNotEmpty) ...[
        Row(
          children: [
            const Expanded(child: ListHeader('Pagos pendientes')),
            TextButton(
              onPressed: _openPayments,
              child: const Text('Ver todos'),
            ),
          ],
        ),
        for (final c in urgent.take(3))
          ChargeCard(charge: c, onTap: () => _openCharge(c)),
        const SizedBox(height: 10),
      ],
    ];
    final content = AsyncListView(
      loading: dependents == null,
      error: _error,
      onRetry: _load,
      padding: EdgeInsets.fromLTRB(16, widget.embedded ? 16 : 4, 16, 100),
      hero: widget.embedded
          ? null
          : _FamilyHeader(
              user: _user,
              summary: _summary,
              onProfile: _openProfile,
              balance: _balance,
              onBalance: _openPayments,
            ),
      header: widget.embedded
          ? Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                _summary,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            )
          : null,
      empty: EmptyState(
        icon: Icons.family_restroom_rounded,
        title: 'Aún no registras a tus hijos',
        message: 'Agrégalos con su CUI para ver sus pagos e inscripciones.',
        actionLabel: 'Agregar hijo',
        onAction: _openForm,
      ),
      children: [
        if (list.isNotEmpty) ...payments,
        if (list.isNotEmpty) const ListHeader('Tus hijos'),
        ...list,
      ],
    );

    return Scaffold(
      appBar: widget.embedded ? pageAppBar(context, 'Mi familia') : null,
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
        edgeOffset: widget.embedded ? 0 : 80,
        child: content,
      ),
    );
  }
}

/// Cabecera del inicio del padre: marca, saludo y acceso al perfil.
class _FamilyHeader extends StatelessWidget {
  const _FamilyHeader({
    required this.user,
    required this.summary,
    required this.onProfile,
    required this.balance,
    required this.onBalance,
  });

  final AppUser user;
  final String summary;
  final VoidCallback onProfile;
  final Balance? balance;
  final VoidCallback onBalance;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return BrandHeader(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.sports_baseball_rounded,
                      color: AppColors.navy,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'MI FAMILIA',
                    style: text.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
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
                'Hola, ${user.displayName}',
                style: text.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              BalanceHeaderCard(balance: balance, onTap: onBalance),
            ],
          ),
        ),
      ),
    );
  }
}

class _DependentCard extends StatelessWidget {
  const _DependentCard({
    required this.dependent,
    required this.categoryName,
    required this.owed,
    required this.onEdit,
    required this.onRemove,
  });

  final Dependent dependent;
  final String categoryName;

  /// Saldo pendiente del hijo; null si no se pudo consultar.
  final double? owed;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListCard(
      onTap: onEdit,
      leading: AppAvatar(
        seed: dependent.cui,
        initials: dependent.initials,
        size: 50,
      ),
      title: dependent.fullName,
      subtitle: 'CUI ${dependent.formattedCui}',
      footer: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Pill(
            categoryName,
            tone: PillTone.brand,
            icon: Icons.sports_baseball_outlined,
          ),
          if (owed != null)
            owed! > 0
                ? Pill(
                    'Debe ${formatMoney(owed!)}',
                    tone: PillTone.warning,
                    icon: Icons.schedule_rounded,
                  )
                : const Pill(
                    'Solvente',
                    tone: PillTone.success,
                    icon: Icons.verified_rounded,
                  ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Opciones',
        icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
        onSelected: (v) => v == 'edit' ? onEdit() : onRemove(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Editar')),
          PopupMenuItem(
            value: 'remove',
            child: Text('Quitar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

/// Saldo dentro de "Mi familia" abierta desde el panel de admin.
class _EmbeddedBalance extends StatelessWidget {
  const _EmbeddedBalance({required this.balance, required this.onTap});

  final Balance balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListCard(
    onTap: onTap,
    leading: AppAvatar(
      seed: 'saldo',
      icon: balance.solvent
          ? Icons.verified_rounded
          : Icons.account_balance_wallet_outlined,
    ),
    title: balance.solvent ? 'Solvente' : formatMoney(balance.totalOwed),
    subtitle: balance.solvent
        ? 'Estás al día con el club'
        : 'Saldo pendiente · toca para ver tus pagos',
  );
}
