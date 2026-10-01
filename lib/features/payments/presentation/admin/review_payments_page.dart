import 'package:flutter/material.dart';

import '../../../../app/app_colors.dart';
import '../../../../core/access/permissions.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/paged_list.dart';
import '../../../auth/data/app_user.dart';
import '../../data/payment_models.dart';
import '../../data/payments_repository.dart';
import '../charge_detail_page.dart';
import '../charge_widgets.dart';
import '../voucher_image.dart';
import '../../../../core/widgets/form_ready.dart';

/// Comprobantes esperando validación (requiere `pagos.validar`), del más
/// antiguo al más reciente.
class ReviewPaymentsPage extends StatefulWidget {
  const ReviewPaymentsPage({super.key, required this.user, this.openChargeId});

  final AppUser user;

  /// Abre directo ese cobro (desde una notificación).
  final String? openChargeId;

  @override
  State<ReviewPaymentsPage> createState() => _ReviewPaymentsPageState();
}

class _ReviewPaymentsPageState extends State<ReviewPaymentsPage> {
  late String? _autoOpen = widget.openChargeId;

  late final _list = PagedController<Charge>(
    (page, pageSize) =>
        PaymentsRepository.instance.reviewQueue(page: page, pageSize: pageSize),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _list.refresh();
    if (!mounted) return;
    // Desde una notificación: abre directo ese comprobante si sigue en cola.
    final target = _list.items?.where((c) => c.id == _autoOpen).firstOrNull;
    _autoOpen = null;
    if (target != null) await _open(target);
  }

  Future<void> _open(Charge c) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReviewVoucherPage(charge: c)),
    );
    if (done == true) {
      _list.update((items) => items.removeWhere((x) => x.id == c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.paymentsReview)) {
      return const NoAccessView();
    }
    return Scaffold(
      appBar: pageAppBar(context, 'Validar pagos'),
      body: PagedListView<Charge>(
        controller: _list,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        header: const ListHeader('Por validar · más antiguos primero'),
        empty: const EmptyState(
          icon: Icons.task_alt_rounded,
          title: 'Todo al día',
          message: 'No hay comprobantes esperando validación.',
        ),
        itemBuilder: (context, c) =>
            ChargeCard(charge: c, showParent: true, onTap: () => _open(c)),
      ),
    );
  }
}

/// Revisar un comprobante: aprobar o rechazar con motivo obligatorio.
/// Devuelve true si se resolvió.
class ReviewVoucherPage extends StatefulWidget {
  const ReviewVoucherPage({super.key, required this.charge});

  final Charge charge;

  @override
  State<ReviewVoucherPage> createState() => _ReviewVoucherPageState();
}

class _ReviewVoucherPageState extends State<ReviewVoucherPage> {
  bool _saving = false;

  Future<void> _approve() async {
    final c = widget.charge;
    final ok = await confirmAction(
      context,
      title: '¿Aprobar el pago?',
      message:
          'Confirmas que recibiste ${formatMoney(c.amount)} por '
          '"${c.concept}". El padre verá el cobro como pagado.',
      confirmLabel: 'Aprobar',
      destructive: false,
    );
    if (ok) await _decide(approve: true);
  }

  Future<void> _reject() async {
    final comment = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _RejectSheet(),
    );
    if (comment != null) await _decide(approve: false, comment: comment);
  }

  Future<void> _decide({required bool approve, String? comment}) async {
    final voucher = widget.charge.voucher;
    if (voucher == null) return;
    setState(() => _saving = true);
    try {
      await PaymentsRepository.instance.reviewVoucher(
        voucher.id,
        approve: approve,
        comment: comment,
      );
      if (!mounted) return;
      showAppMessage(
        context,
        approve
            ? 'Pago aprobado. El padre ya lo ve como pagado.'
            : 'Comprobante rechazado. El padre verá el motivo.',
      );
      Navigator.of(context).pop(true);
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.charge;
    final v = c.voucher;
    return Scaffold(
      appBar: pageAppBar(context, 'Revisar comprobante'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (v != null && v.suspectedEdit) ...[
            _EditWarning(signals: v.editSignalList),
            const SizedBox(height: 12),
          ],
          if (v != null) VoucherImage(voucher: v),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.concept,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(c.amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: AppColors.border),
                if (c.parentName != null) _Row('Padre/madre', c.parentName!),
                if (c.parentEmail != null) _Row('Correo', c.parentEmail!),
                _Row(
                  'Tipo',
                  [
                    c.type.label,
                    if (c.period != null) formatPeriod(c.period!),
                  ].join(' · '),
                ),
                if (c.dueDate != null) _Row('Vence', formatDate(c.dueDate!)),
                if (v != null && c.dueDate != null)
                  _Row(
                    'A tiempo',
                    daysUntil(c.dueDate!, now: v.uploadedAt) >= 0
                        ? 'Sí, subido antes del vencimiento'
                        : 'No, subido después del vencimiento',
                  ),
              ],
            ),
          ),
          if (v != null) ...[
            const SizedBox(height: 16),
            const ListHeader('Datos del comprobante'),
            VoucherDetails(voucher: v, chargeAmount: c.amount),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _approve,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Aprobar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Advertencia visible: la foto podría estar editada (no es prueba).
class _EditWarning extends StatelessWidget {
  const _EditWarning({required this.signals});
  final List<String> signals;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Posible imagen editada',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final s in signals)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $s', style: const TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 6),
        const Text(
          'Son indicios, no pruebas: verifica el depósito en el banco antes '
          'de aprobar.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

/// Motivo del rechazo: obligatorio, lo verá el padre tal cual.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet();

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> with FormReady {
  final _formKey = GlobalKey<FormState>();
  final _comment = TextEditingController();

  static const _suggestions = [
    'La imagen no se lee con claridad.',
    'El monto no coincide con el cobro.',
    'No encontramos el depósito en el banco.',
    'El comprobante corresponde a otro pago.',
  ];

  static String? _commentError(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'El motivo es obligatorio';
    if (t.length < 10) return 'Explica un poco más (mín. 10)';
    if (t.length > 500) return 'Máximo 500 caracteres';
    return null;
  }

  @override
  void initState() {
    super.initState();
    watchFields([_comment]);
  }

  @override
  void dispose() {
    _comment.dispose();
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
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Motivo del rechazo',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'El padre lo verá junto con un botón para contactar al club.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in _suggestions)
                  ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => _comment.text = s),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _comment,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Explica qué está mal con el comprobante',
              ),
              validator: _commentError,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: _commentError(_comment.text) != null
                  ? null
                  : () => Navigator.of(context).pop(_comment.text.trim()),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Rechazar comprobante'),
            ),
          ],
        ),
      ),
    );
  }
}
