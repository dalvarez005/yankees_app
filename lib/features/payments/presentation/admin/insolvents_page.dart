import 'package:flutter/material.dart';

import '../../../../app/app_colors.dart';
import '../../../../core/access/permissions.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/filter_bar.dart';
import '../../../../core/widgets/paged_list.dart';
import '../../../auth/data/app_user.dart';
import '../../../categories/data/category_repository.dart';
import '../../data/payment_models.dart';
import '../../data/payments_repository.dart';

/// Familias con pagos vencidos (requiere `pagos.gestionar`): resumen del
/// club, filtro por categoría de sus hijos y recordatorios in-app.
class InsolventsPage extends StatefulWidget {
  const InsolventsPage({super.key, required this.user});

  final AppUser user;

  @override
  State<InsolventsPage> createState() => _InsolventsPageState();
}

class _InsolventsPageState extends State<InsolventsPage> {
  SolvencyReport? _report;
  List<Category> _categories = const [];
  String _search = '';
  Map<String, Object?> _filters = const {};
  final _selected = <String>{};
  bool _sending = false;

  /// Total que informa la API para el filtro actual (si lo manda).
  int? _total;

  late final _list = PagedController<InsolventUser>((page, pageSize) async {
    final result = await PaymentsRepository.instance.insolventUsers(
      categoryId: _filters['category'] as int?,
      search: _search,
      page: page,
      pageSize: pageSize,
    );
    _total = result.totalRecords;
    return result.users;
  });

  @override
  void initState() {
    super.initState();
    _list.refresh();
    _loadReport();
    _loadCategories();
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  /// Si falla, la lista funciona igual sin el resumen.
  Future<void> _loadReport() async {
    try {
      final r = await PaymentsRepository.instance.solvencyReport();
      if (mounted) setState(() => _report = r);
    } on PaymentsException {
      // Sin resumen.
    }
  }

  Future<void> _loadCategories() async {
    try {
      final list = await CategoryRepository.instance.list();
      if (mounted) {
        setState(() => _categories = [...list.where((c) => c.active)]);
      }
    } on CategoryException {
      // Sin filtro por categoría.
    }
  }

  Future<void> _load() async {
    await _list.refresh(keepItems: true);
    // Solo quedan seleccionados los que siguen en la lista.
    final ids = {
      for (final u in _list.items ?? const <InsolventUser>[]) u.userId,
    };
    if (mounted) setState(() => _selected.retainAll(ids));
  }

  /// [ids] null = todos los insolventes del club.
  Future<void> _notify(List<String>? ids) async {
    final total = ids?.length ?? _report?.insolventUsers ?? _total;
    final who = ids == null
        ? 'todos los insolventes${total == null ? '' : ' ($total)'}'
        : ids.length == 1
        ? '1 usuario'
        : '${ids.length} usuarios';
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _NotifySheet(who: who),
    );
    if (message == null || !mounted) return;
    final ok = await confirmAction(
      context,
      title: '¿Enviar recordatorio a $who?',
      message:
          'Recibirán una notificación con el monto que tienen vencido. A '
          'quien ya se le recordó en las últimas 24 horas no se le vuelve '
          'a enviar.',
      confirmLabel: 'Enviar',
      destructive: false,
    );
    if (!ok) return;
    setState(() => _sending = true);
    try {
      final r = await PaymentsRepository.instance.notifyInsolvents(
        userIds: ids,
        message: message,
      );
      if (!mounted) return;
      final sent = r.notified == 1
          ? 'Se notificó a 1 usuario.'
          : 'Se notificó a ${r.notified} usuarios.';
      final skipped = r.skipped == 0
          ? ''
          : ' ${r.skipped} ${r.skipped == 1 ? 'omitido' : 'omitidos'} '
                '(ya se les recordó en las últimas 24 h).';
      showAppMessage(context, '$sent$skipped');
      setState(_selected.clear);
      await _load();
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.paymentsManage)) {
      return const NoAccessView();
    }
    return Scaffold(
      appBar: pageAppBar(context, 'Insolventes'),
      body: Column(
        children: [
          FilterBar(
            searchHint: 'Buscar por nombre o correo',
            filters: [
              if (_categories.isNotEmpty)
                FilterSpec(
                  key: 'category',
                  title: 'Categoría de sus hijos',
                  icon: Icons.sports_baseball_outlined,
                  choices: [
                    for (final c in _categories) FilterChoice(c.id, c.name),
                  ],
                ),
            ],
            values: _filters,
            search: _search,
            onChanged: (search, values) {
              setState(() {
                _search = search;
                _filters = values;
                _selected.clear();
              });
              _list.refresh();
            },
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _list,
              builder: (context, _) {
                final users = _list.items ?? const <InsolventUser>[];
                final allSelected =
                    users.isNotEmpty &&
                    users.every((u) => _selected.contains(u.userId));
                return PagedListView<InsolventUser>(
                  controller: _list,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  header: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_report != null) _ReportCard(report: _report!),
                      Row(
                        children: [
                          Expanded(
                            child: ListHeader(
                              'Con pagos vencidos',
                              count: _total ?? users.length,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              if (allSelected) {
                                _selected.clear();
                              } else {
                                _selected.addAll(users.map((u) => u.userId));
                              }
                            }),
                            child: Text(
                              allSelected
                                  ? 'Quitar selección'
                                  : 'Seleccionar visibles',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  empty: EmptyState(
                    icon: Icons.verified_rounded,
                    title: 'Nadie con pagos vencidos',
                    message: _filters.isEmpty && _search.isEmpty
                        ? 'Todas las familias están al día.'
                        : 'Ninguna familia con pagos vencidos coincide con '
                              'la búsqueda o el filtro.',
                  ),
                  itemBuilder: (context, u) => _InsolventTile(
                    user: u,
                    selected: _selected.contains(u.userId),
                    onChanged: (v) => setState(
                      () => v
                          ? _selected.add(u.userId)
                          : _selected.remove(u.userId),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ListenableBuilder(
            listenable: _list,
            builder: (context, _) => _selected.isEmpty
                ? FilledButton.icon(
                    onPressed: _sending || (_list.items?.isEmpty ?? true)
                        ? null
                        : () => _notify(null),
                    icon: const Icon(Icons.campaign_rounded),
                    label: const Text('Notificar a todos los insolventes'),
                  )
                : FilledButton.icon(
                    onPressed: _sending
                        ? null
                        : () => _notify(_selected.toList()),
                    icon: const Icon(Icons.notifications_active_rounded),
                    label: Text(
                      'Notificar seleccionados (${_selected.length})',
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});
  final SolvencyReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    Widget tile(String label, String value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: color ?? AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.period == null
                ? 'Resumen'
                : 'Resumen · ${formatPeriod(r.period!)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              tile(
                'Insolventes',
                '${r.insolventUsers} de ${r.approvedUsers}',
                color: r.insolventUsers > 0 ? AppColors.error : null,
              ),
              tile(
                'Vencido',
                formatMoney(r.overdueAmount),
                color: r.overdueAmount > 0 ? AppColors.error : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              tile(
                'Cobrado este mes',
                formatMoney(r.collectedThisPeriod),
                color: AppColors.success,
              ),
              tile('En revisión', formatMoney(r.inReviewAmount)),
            ],
          ),
          if (r.pendingValidationUsers > 0) ...[
            const SizedBox(height: 10),
            Pill(
              '${r.pendingValidationUsers} por validar',
              tone: PillTone.warning,
              icon: Icons.how_to_reg_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _InsolventTile extends StatelessWidget {
  const _InsolventTile({
    required this.user,
    required this.selected,
    required this.onChanged,
  });

  final InsolventUser user;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final kids = u.dependents
        .map(
          (d) =>
              d.categoryName == null ? d.name : '${d.name} (${d.categoryName})',
        )
        .join(', ');
    return ListCard(
      onTap: () => onChanged(!selected),
      leading: AppAvatar(
        seed: u.email,
        initials: u.name
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join(),
      ),
      title: u.name.isEmpty ? u.email : u.name,
      subtitle: kids.isEmpty ? u.email : '${u.email}\n$kids',
      subtitleLines: 2,
      footer: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Pill(
            '${formatMoney(u.overdueAmount)} vencido',
            tone: PillTone.danger,
            icon: Icons.warning_amber_rounded,
          ),
          Pill(
            u.overdueCharges == 1 ? '1 cobro' : '${u.overdueCharges} cobros',
            tone: PillTone.neutral,
          ),
          if (u.oldestDueDate != null)
            Pill(
              'Desde ${formatDate(u.oldestDueDate!)}',
              icon: Icons.schedule_rounded,
            ),
          if (u.lastReminderAt != null)
            Pill(
              'Recordado ${formatDate(u.lastReminderAt!)}',
              tone: PillTone.brand,
              icon: Icons.notifications_active_outlined,
            ),
        ],
      ),
      trailing: Checkbox(
        value: selected,
        onChanged: (v) => onChanged(v ?? false),
        activeColor: AppColors.navy,
      ),
    );
  }
}

/// Mensaje opcional para el recordatorio (máx. 300). Devuelve el texto
/// (puede ser vacío) o null si se cancela.
class _NotifySheet extends StatefulWidget {
  const _NotifySheet({required this.who});
  final String who;

  @override
  State<_NotifySheet> createState() => _NotifySheetState();
}

class _NotifySheetState extends State<_NotifySheet> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recordatorio de pago',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Para ${widget.who}. El aviso ya incluye el monto vencido de '
            'cada familia; puedes agregar un mensaje.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _message,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Mensaje opcional (p. ej. fecha límite o dónde pagar)',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_message.text.trim()),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Continuar'),
          ),
        ],
      ),
    );
  }
}
