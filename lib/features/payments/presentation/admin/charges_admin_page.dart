import 'package:flutter/material.dart';

import '../../../../app/app_colors.dart';
import '../../../../core/access/permissions.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../auth/data/app_user.dart';
import '../../data/payment_models.dart';
import '../../data/payments_repository.dart';
import '../charge_widgets.dart';

/// Todos los cobros (requiere `pagos.gestionar`): filtrar por estado, tipo
/// y período, buscar y anular los que no se pagaron. Los cobros los genera
/// la API (inscripción al validar, mensualidad cada mes).
class ChargesAdminPage extends StatefulWidget {
  const ChargesAdminPage({super.key, required this.user});

  final AppUser user;

  @override
  State<ChargesAdminPage> createState() => _ChargesAdminPageState();
}

class _ChargesAdminPageState extends State<ChargesAdminPage> {
  final _search = TextEditingController();
  List<Charge>? _charges;
  ChargeStatus? _status;
  ChargeType? _type;
  String? _period;
  String? _error;

  static const _statuses = [
    (null, 'Todos'),
    (ChargeStatus.pending, 'Por pagar'),
    (ChargeStatus.inReview, 'En revisión'),
    (ChargeStatus.rejected, 'Rechazados'),
    (ChargeStatus.paid, 'Pagados'),
    (ChargeStatus.cancelled, 'Anulados'),
  ];

  /// Los últimos 12 meses, el actual primero.
  static List<String> get _periods {
    final now = DateTime.now();
    return [
      for (var i = 0; i < 12; i++) periodOf(DateTime(now.year, now.month - i)),
    ];
  }

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
        status: _status,
        type: _type,
        period: _period,
        search: _search.text,
      );
      if (mounted) setState(() => _charges = charges);
    } on PaymentsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _apply(VoidCallback change) {
    setState(() {
      change();
      _charges = null;
    });
    _load();
  }

  Future<void> _cancel(Charge c) async {
    final ok = await confirmAction(
      context,
      title: '¿Anular "${c.concept}"?',
      message:
          '${c.parentName ?? 'La familia'} ya no deberá '
          '${formatMoney(c.amount)} por este cobro.'
          '${c.status == ChargeStatus.inReview ? ' El comprobante en revisión quedará rechazado.' : ''}',
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

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.navy,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.text,
        fontWeight: FontWeight.w500,
      ),
      showCheckmark: false,
      side: const BorderSide(color: AppColors.border),
      backgroundColor: AppColors.surface,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.paymentsManage)) {
      return const NoAccessView();
    }
    final charges = _charges;
    final total = charges
        ?.where((c) => c.status.owes)
        .fold<double>(0, (sum, c) => sum + c.amount);
    final filtered =
        _status != null ||
        _type != null ||
        _period != null ||
        _search.text.trim().isNotEmpty;
    return Scaffold(
      appBar: pageAppBar(context, 'Cobros'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Buscar por padre, correo o concepto',
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
                for (final (status, label) in _statuses)
                  _chip(
                    label,
                    _status == status,
                    () => _apply(() => _status = status),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip(
                  'Todo tipo',
                  _type == null,
                  () => _apply(() => _type = null),
                ),
                for (final t in ChargeType.values)
                  _chip(t.label, _type == t, () => _apply(() => _type = t)),
                // "" = todos (un valor null se toma como cancelar).
                PopupMenuButton<String>(
                  tooltip: 'Período',
                  initialValue: _period ?? '',
                  onSelected: (p) =>
                      _apply(() => _period = p.isEmpty ? null : p),
                  itemBuilder: (_) => [
                    const PopupMenuItem<String>(
                      value: '',
                      child: Text('Todos los períodos'),
                    ),
                    for (final p in _periods)
                      PopupMenuItem<String>(
                        value: p,
                        child: Text(formatPeriod(p)),
                      ),
                  ],
                  child: Chip(
                    avatar: Icon(
                      Icons.calendar_month_rounded,
                      size: 18,
                      color: _period == null ? AppColors.text : Colors.white,
                    ),
                    label: Text(
                      _period == null ? 'Período' : formatPeriod(_period!),
                      style: TextStyle(
                        color: _period == null ? AppColors.text : Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    backgroundColor: _period == null
                        ? AppColors.surface
                        : AppColors.navy,
                    side: const BorderSide(color: AppColors.border),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
                  message: filtered
                      ? 'Ningún cobro coincide con el filtro.'
                      : 'Los cobros se generan solos: la inscripción al '
                            'validar a un usuario y la mensualidad cada mes.',
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
