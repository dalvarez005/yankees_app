import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_colors.dart';
import '../../../../core/access/permissions.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../auth/data/app_user.dart';
import '../../../auth/presentation/widgets/auth_field.dart';
import '../../../auth/presentation/widgets/loading_button.dart';
import '../../../categories/data/category_repository.dart';
import '../../data/payment_models.dart';
import '../../data/payments_repository.dart';
import '../charge_widgets.dart';

/// Cobros asignados (requiere `pagos.asignar`): filtrar, buscar, asignar
/// nuevos y anular los que no se pagaron.
class ChargesAdminPage extends StatefulWidget {
  const ChargesAdminPage({super.key, required this.user});

  final AppUser user;

  @override
  State<ChargesAdminPage> createState() => _ChargesAdminPageState();
}

class _ChargesAdminPageState extends State<ChargesAdminPage> {
  final _search = TextEditingController();
  List<Charge>? _charges;
  ChargeStatus? _filter;
  String? _error;

  static const _filters = [
    (null, 'Todos'),
    (ChargeStatus.pending, 'Por pagar'),
    (ChargeStatus.inReview, 'En revisión'),
    (ChargeStatus.rejected, 'Rechazados'),
    (ChargeStatus.paid, 'Pagados'),
    (ChargeStatus.cancelled, 'Anulados'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final charges = await PaymentsRepository.instance.charges(
        status: _filter,
        search: _search.text,
      );
      if (mounted) setState(() => _charges = charges);
    } on PaymentsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _setFilter(ChargeStatus? f) {
    setState(() {
      _filter = f;
      _charges = null;
    });
    _load();
  }

  Future<void> _assign() async {
    final created = await Navigator.of(context)
        .push<int>(MaterialPageRoute(builder: (_) => const AssignChargePage()));
    if (created == null || !mounted) return;
    showAppMessage(
      context,
      created == 1 ? 'Cobro asignado.' : 'Se asignaron $created cobros.',
    );
    await _load();
  }

  Future<void> _cancel(Charge c) async {
    final ok = await confirmAction(
      context,
      title: '¿Anular "${c.concept}"?',
      message:
          '${c.dependentName} ya no deberá ${formatMoney(c.amount)} por '
          'este cobro.',
      confirmLabel: 'Anular',
    );
    if (!ok) return;
    try {
      await PaymentsRepository.instance.cancelCharge(c.id);
      if (!mounted) return;
      showAppMessage(context, 'Cobro anulado.');
      await _load();
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.chargesAssign)) {
      return const NoAccessView();
    }
    final charges = _charges;
    final total = charges
        ?.where((c) => c.status.owes)
        .fold<double>(0, (sum, c) => sum + c.amount);
    return Scaffold(
      appBar: pageAppBar(context, 'Cobros'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _assign,
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Asignar cobro'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Buscar por hijo o concepto',
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
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (status, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == status,
                      onSelected: (_) => _setFilter(status),
                      selectedColor: AppColors.navy,
                      labelStyle: TextStyle(
                        color: _filter == status
                            ? Colors.white
                            : AppColors.text,
                        fontWeight: FontWeight.w500,
                      ),
                      showCheckmark: false,
                      side: const BorderSide(color: AppColors.border),
                      backgroundColor: AppColors.surface,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: AsyncListView(
                loading: charges == null,
                error: _error,
                onRetry: _load,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                header: charges == null || charges.isEmpty
                    ? null
                    : Row(
                        children: [
                          Expanded(
                            child: ListHeader('Cobros', count: charges.length),
                          ),
                          if (total != null && total > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Por cobrar ${formatMoney(total)}',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                empty: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Sin cobros',
                  message: _filter == null && _search.text.trim().isEmpty
                      ? 'Asigna el primero: una mensualidad, la inscripción…'
                      : 'Ningún cobro coincide con el filtro.',
                ),
                children: [
                  for (final c in charges ?? const <Charge>[])
                    ChargeCard(
                      charge: c,
                      showParent: true,
                      trailing: c.status.owes
                          ? PopupMenuButton<String>(
                              tooltip: 'Opciones',
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                color: AppColors.textMuted,
                              ),
                              onSelected: (_) => _cancel(c),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'cancel',
                                  child: Text(
                                    'Anular cobro',
                                    style: TextStyle(color: AppColors.error),
                                  ),
                                ),
                              ],
                            )
                          : null,
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

/// Asignar un cobro a un hijo o a todos los de una categoría.
/// Devuelve cuántos cobros se crearon.
class AssignChargePage extends StatefulWidget {
  const AssignChargePage({super.key});

  @override
  State<AssignChargePage> createState() => _AssignChargePageState();
}

enum _Target { category, dependent }

class _AssignChargePageState extends State<AssignChargePage> {
  final _formKey = GlobalKey<FormState>();
  final _concept = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _kidSearch = TextEditingController();

  _Target _target = _Target.category;
  DateTime? _dueDate;
  List<Category> _categories = const [];
  int? _categoryId;
  List<ChargeTargetDependent> _kids = const [];
  ChargeTargetDependent? _kid;
  Timer? _debounce;
  bool _saving = false;

  static const _presets = [
    'Inscripción',
    'Mensualidad',
    'Uniforme',
    'Torneo',
    'Transporte',
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _searchKids('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_concept, _description, _amount, _kidSearch]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final list = await CategoryRepository.instance.list();
      if (mounted) {
        setState(() => _categories = [...list.where((c) => c.active)]);
      }
    } on CategoryException {
      // Se puede asignar por hijo igual.
    }
  }

  void _onKidSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _searchKids(q));
  }

  Future<void> _searchKids(String q) async {
    try {
      final kids = await PaymentsRepository.instance.searchDependents(q);
      if (mounted) setState(() => _kids = kids);
    } on PaymentsException {
      if (mounted) setState(() => _kids = const []);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 15)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      helpText: 'Fecha límite de pago',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  double? get _amountValue =>
      double.tryParse(_amount.text.replaceAll(',', '').trim());

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_target == _Target.category && _categoryId == null) {
      showAppMessage(context, 'Elige la categoría.', error: true);
      return;
    }
    if (_target == _Target.dependent && _kid == null) {
      showAppMessage(context, 'Elige a quién se le cobra.', error: true);
      return;
    }
    final categoryName = _categories
        .where((c) => c.id == _categoryId)
        .map((c) => c.name)
        .firstOrNull;
    final ok = await confirmAction(
      context,
      title: 'Confirmar cobro',
      message: _target == _Target.category
          ? 'Se cobrará ${formatMoney(_amountValue!)} por '
                '"${_concept.text.trim()}" a cada hijo de la categoría '
                '$categoryName.'
          : 'Se cobrará ${formatMoney(_amountValue!)} por '
                '"${_concept.text.trim()}" a ${_kid!.name}.',
      confirmLabel: 'Asignar',
      destructive: false,
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      final created = await PaymentsRepository.instance.assignCharge(
        concept: _concept.text,
        description: _description.text,
        amount: _amountValue!,
        dueDate: _dueDate,
        dependentId: _target == _Target.dependent ? _kid!.id : null,
        categoryId: _target == _Target.category ? _categoryId : null,
      );
      if (!mounted) return;
      if (created == 0) {
        showAppMessage(
          context,
          'Esa categoría no tiene hijos registrados.',
          info: true,
        );
        return;
      }
      Navigator.of(context).pop(created);
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageAppBar(context, 'Asignar cobro'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            AuthField(
              label: 'Concepto',
              hint: 'Ej. Mensualidad de octubre',
              icon: Icons.receipt_long_outlined,
              controller: _concept,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'El concepto es obligatorio';
                if (t.length > 100) return 'Máximo 100 caracteres';
                return null;
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final p in _presets)
                  ActionChip(
                    label: Text(p, style: const TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => _concept.text = p),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AuthField(
              label: 'Monto (Q)',
              hint: 'Ej. 150.00',
              icon: Icons.payments_outlined,
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              validator: (_) {
                final a = _amountValue;
                if (a == null) return 'Escribe el monto';
                if (a <= 0) return 'El monto debe ser mayor a cero';
                if (a > 100000) return 'Monto demasiado alto';
                return null;
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Fecha límite (opcional)',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDate,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                alignment: Alignment.centerLeft,
                foregroundColor: AppColors.text,
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.event_rounded, color: AppColors.textMuted),
              label: Text(
                _dueDate == null ? 'Sin fecha límite' : formatDate(_dueDate!),
              ),
            ),
            const SizedBox(height: 16),
            AuthField(
              label: 'Detalle (opcional)',
              hint: 'Ej. Incluye camisola y gorra',
              icon: Icons.notes_rounded,
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v?.length ?? 0) > 250 ? 'Máximo 250 caracteres' : null,
            ),
            const SizedBox(height: 24),
            const Text(
              '¿A quién se le cobra?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 10),
            SegmentedButton<_Target>(
              segments: const [
                ButtonSegment(
                  value: _Target.category,
                  icon: Icon(Icons.groups_rounded),
                  label: Text('Categoría'),
                ),
                ButtonSegment(
                  value: _Target.dependent,
                  icon: Icon(Icons.person_rounded),
                  label: Text('Un hijo'),
                ),
              ],
              selected: {_target},
              onSelectionChanged: (s) => setState(() => _target = s.first),
            ),
            const SizedBox(height: 14),
            if (_target == _Target.category)
              DropdownButtonFormField<int>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  prefixIcon: Icon(Icons.sports_baseball_outlined, size: 20),
                ),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              )
            else ...[
              TextField(
                controller: _kidSearch,
                onChanged: _onKidSearch,
                decoration: const InputDecoration(
                  hintText: 'Buscar por nombre o CUI',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              if (_kids.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Sin resultados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              for (final k in _kids.take(8))
                ListCard(
                  onTap: () => setState(() => _kid = k),
                  leading: AppAvatar(
                    seed: k.id,
                    initials: k.name
                        .split(' ')
                        .where((p) => p.isNotEmpty)
                        .take(2)
                        .map((p) => p[0].toUpperCase())
                        .join(),
                    size: 40,
                  ),
                  title: k.name,
                  subtitle: [?k.categoryName, ?k.parentName].join(' · '),
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      _kid?.id == k.id
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: _kid?.id == k.id
                          ? AppColors.navy
                          : AppColors.textMuted,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Asignar cobro',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
