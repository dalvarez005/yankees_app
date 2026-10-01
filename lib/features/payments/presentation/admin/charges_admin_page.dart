import 'package:flutter/material.dart';

import '../../../../app/app_colors.dart';
import '../../../../core/access/permissions.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/filter_bar.dart';
import '../../../../core/widgets/paged_list.dart';
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
  String _search = '';
  Map<String, Object?> _filters = const {};

  late final _list = PagedController<Charge>(
    (page, pageSize) => PaymentsRepository.instance.charges(
      status: _filters['status'] as ChargeStatus?,
      type: _filters['type'] as ChargeType?,
      period: _filters['period'] as String?,
      search: _search,
      page: page,
      pageSize: pageSize,
    ),
  );

  /// Los últimos 12 meses, el actual primero.
  static List<FilterChoice> get _periods {
    final now = DateTime.now();
    return [
      for (var i = 0; i < 12; i++)
        FilterChoice(
          periodOf(DateTime(now.year, now.month - i)),
          formatPeriod(periodOf(DateTime(now.year, now.month - i))),
        ),
    ];
  }

  static final _specs = [
    const FilterSpec(
      key: 'status',
      title: 'Estado',
      icon: Icons.flag_outlined,
      choices: [
        FilterChoice(ChargeStatus.pending, 'Por pagar'),
        FilterChoice(ChargeStatus.inReview, 'En revisión'),
        FilterChoice(ChargeStatus.rejected, 'Rechazados'),
        FilterChoice(ChargeStatus.paid, 'Pagados'),
        FilterChoice(ChargeStatus.cancelled, 'Anulados'),
      ],
    ),
    FilterSpec(
      key: 'type',
      title: 'Tipo',
      icon: Icons.category_outlined,
      choices: [for (final t in ChargeType.values) FilterChoice(t, t.label)],
    ),
    FilterSpec(
      key: 'period',
      title: 'Período',
      icon: Icons.calendar_month_rounded,
      choices: _periods,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _list.refresh();
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
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
      await _list.refresh(keepItems: true);
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.paymentsManage)) {
      return const NoAccessView();
    }
    final filtered = _filters.isNotEmpty || _search.isNotEmpty;
    return Scaffold(
      appBar: pageAppBar(context, 'Cobros'),
      body: Column(
        children: [
          FilterBar(
            searchHint: 'Buscar por padre, correo o concepto',
            filters: _specs,
            values: _filters,
            search: _search,
            onChanged: (search, values) {
              setState(() {
                _search = search;
                _filters = values;
              });
              _list.refresh();
            },
          ),
          Expanded(
            child: PagedListView<Charge>(
              controller: _list,
              empty: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Sin cobros',
                message: filtered
                    ? 'Ningún cobro coincide con la búsqueda o los filtros.'
                    : 'Los cobros se generan solos: la inscripción al '
                          'validar a un usuario y la mensualidad cada mes.',
              ),
              itemBuilder: (context, c) => ChargeCard(
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
            ),
          ),
        ],
      ),
    );
  }
}
