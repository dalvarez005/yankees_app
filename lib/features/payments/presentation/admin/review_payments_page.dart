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
import '../voucher_image.dart';

/// Comprobantes esperando validación (requiere `pagos.validar`), del más
/// antiguo al más reciente.
class ReviewPaymentsPage extends StatefulWidget {
  const ReviewPaymentsPage({super.key, required this.user});

  final AppUser user;

  @override
  State<ReviewPaymentsPage> createState() => _ReviewPaymentsPageState();
}

class _ReviewPaymentsPageState extends State<ReviewPaymentsPage> {
  List<Charge>? _queue;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final queue = await PaymentsRepository.instance.reviewQueue();
      if (mounted) setState(() => _queue = queue);
    } on PaymentsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open(Charge c) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReviewVoucherPage(charge: c)),
    );
    if (done == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.paymentsReview)) {
      return const NoAccessView();
    }
    final queue = _queue;
    return Scaffold(
      appBar: pageAppBar(context, 'Validar pagos'),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: AsyncListView(
          loading: queue == null,
          error: _error,
          onRetry: _load,
          header: queue == null || queue.isEmpty
              ? null
              : ListHeader('Por validar', count: queue.length),
          empty: const EmptyState(
            icon: Icons.task_alt_rounded,
            title: 'Todo al día',
            message: 'No hay comprobantes esperando validación.',
          ),
          children: [
            for (final c in queue ?? const <Charge>[])
              ChargeCard(charge: c, showParent: true, onTap: () => _open(c)),
          ],
        ),
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
          if (v != null) VoucherImage(voucher: v, height: 320),
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
                _Row('Hijo', [c.dependentName, ?c.categoryName].join(' · ')),
                if (c.parentName != null) _Row('Padre/madre', c.parentName!),
                if (c.parentEmail != null) _Row('Correo', c.parentEmail!),
                if (v != null) _Row('Enviado', formatDateTime(v.uploadedAt)),
                _Row('Referencia', v?.reference ?? 'No indicó'),
                if (c.dueDate != null) _Row('Vencía', formatDate(c.dueDate!)),
              ],
            ),
          ),
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

class _RejectSheetState extends State<_RejectSheet> {
  final _formKey = GlobalKey<FormState>();
  final _comment = TextEditingController();

  static const _suggestions = [
    'La imagen no se lee con claridad.',
    'El monto no coincide con el cobro.',
    'No encontramos el depósito en el banco.',
    'El comprobante corresponde a otro pago.',
  ];

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
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'El motivo es obligatorio';
                if (t.length < 10) return 'Explica un poco más (mín. 10)';
                return null;
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  Navigator.of(context).pop(_comment.text.trim());
                }
              },
              icon: const Icon(Icons.close_rounded),
              label: const Text('Rechazar comprobante'),
            ),
          ],
        ),
      ),
    );
  }
}
