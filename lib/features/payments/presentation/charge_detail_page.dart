import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_colors.dart';
import '../../../core/contact/whatsapp.dart';
import '../../../core/format/formats.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/money_field.dart';
import '../../auth/presentation/widgets/auth_field.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../data/payment_models.dart';
import '../data/payments_repository.dart';
import '../data/settings_repository.dart';
import '../data/voucher_processor.dart';
import 'charge_widgets.dart';
import 'solvency_page.dart';
import 'voucher_image.dart';

/// Detalle de un cobro para el padre: monto, estado y lo que puede hacer
/// (subir comprobante, contactar si se lo rechazaron, ver su solvencia).
/// Devuelve true al cerrar si el cobro cambió.
class ChargeDetailPage extends StatefulWidget {
  const ChargeDetailPage({super.key, required this.charge});

  final Charge charge;

  @override
  State<ChargeDetailPage> createState() => _ChargeDetailPageState();
}

class _ChargeDetailPageState extends State<ChargeDetailPage> {
  late Charge _charge = widget.charge;
  bool _changed = false;

  Future<void> _upload() async {
    final updated = await Navigator.of(context).push<Charge>(
      MaterialPageRoute(builder: (_) => UploadVoucherPage(charge: _charge)),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _charge = updated;
      _changed = true;
    });
    showAppMessage(
      context,
      'Comprobante enviado. Queda pendiente hasta que el club lo valide.',
    );
  }

  Future<void> _contact() async {
    PaymentSettings contact;
    try {
      contact = await SettingsRepository.instance.paymentSettings();
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
      return;
    }
    if (!contact.hasContact) {
      if (mounted) {
        showAppMessage(
          context,
          'El club aún no configuró un número de contacto.',
          info: true,
        );
      }
      return;
    }
    final c = _charge;
    final ok = await openWhatsApp(
      contact.whatsappNumber,
      message:
          'Hola, me rechazaron el comprobante de "${c.concept}" '
          '(${formatMoney(c.amount)})'
          '${c.voucher?.bankReference == null ? '' : ', boleta ${c.voucher!.bankReference}'}. '
          '¿Me pueden dar más detalles?',
    );
    if (!ok && mounted) {
      showAppMessage(context, 'No se pudo abrir WhatsApp.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _charge;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: pageAppBar(context, 'Detalle del cobro'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _AmountCard(charge: c),
            const SizedBox(height: 14),
            _StatusPanel(charge: c, onUpload: _upload, onContact: _contact),
            if (c.voucher != null) ...[
              const SizedBox(height: 20),
              ListHeader(
                c.voucher!.status == VoucherStatus.rejected
                    ? 'Último comprobante (rechazado)'
                    : 'Comprobante enviado',
              ),
              VoucherImage(voucher: c.voucher!),
              const SizedBox(height: 10),
              VoucherDetails(voucher: c.voucher!),
            ],
          ],
        ),
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.charge});
  final Charge charge;

  @override
  Widget build(BuildContext context) {
    final c = charge;
    return Container(
      padding: const EdgeInsets.all(20),
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
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ChargeStatusPill(c),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatMoney(c.amount),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: c.status == ChargeStatus.paid
                  ? AppColors.success
                  : AppColors.navy,
            ),
          ),
          const Divider(height: 28, color: AppColors.border),
          _InfoRow(
            icon: c.type == ChargeType.enrollment
                ? Icons.how_to_reg_rounded
                : Icons.calendar_month_rounded,
            label: 'Tipo',
            value: [
              c.type.label,
              if (c.period != null) formatPeriod(c.period!),
            ].join(' · '),
          ),
          if (c.dueDate != null)
            _InfoRow(
              icon: Icons.event_rounded,
              label: 'Vence',
              value: formatDate(c.dueDate!),
              danger: c.overdue,
            ),
          _InfoRow(
            icon: Icons.receipt_long_rounded,
            label: 'Generado',
            value: formatDate(c.createdAt),
          ),
          if (c.status == ChargeStatus.paid && c.paidOnTime != null)
            _InfoRow(
              icon: c.paidOnTime!
                  ? Icons.timer_outlined
                  : Icons.running_with_errors_rounded,
              label: 'Pago',
              value: c.paidOnTime! ? 'A tiempo' : 'Después del vencimiento',
              danger: !c.paidOnTime!,
            ),
        ],
      ),
    );
  }
}

/// Lo que corresponde según el estado, con el color de ese estado.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.charge,
    required this.onUpload,
    required this.onContact,
  });

  final Charge charge;
  final VoidCallback onUpload;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final c = charge;
    return switch (c.status) {
      ChargeStatus.pending => _Panel(
        color: c.overdue ? AppColors.error : const Color(0xFFB45309),
        icon: Icons.upload_file_rounded,
        title: c.overdue ? 'Este cobro está vencido' : 'Pendiente de pago',
        message: c.overdue
            ? 'Mientras no lo pagues aparecerás como insolvente. Paga en el '
                  'banco o por transferencia y sube la foto del comprobante.'
            : 'Paga en el banco o por transferencia y sube la foto del '
                  'comprobante antes del vencimiento. El club lo validará.',
        actions: [
          FilledButton.icon(
            onPressed: onUpload,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Subir comprobante'),
          ),
        ],
      ),
      ChargeStatus.inReview => const _Panel(
        color: AppColors.navy,
        icon: Icons.hourglass_top_rounded,
        title: 'Pendiente de validación',
        message:
            'Recibimos tu comprobante. Un administrador del club lo '
            'revisará y te avisaremos el resultado. Mientras tanto no '
            'cuenta como atrasado.',
      ),
      ChargeStatus.rejected => _Panel(
        color: AppColors.error,
        icon: Icons.report_gmailerrorred_rounded,
        title: 'Comprobante rechazado',
        message: 'Motivo indicado por el club:',
        quote: c.voucher?.reviewComment ?? 'Sin comentario.',
        actions: [
          FilledButton.icon(
            onPressed: onContact,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
            ),
            icon: const Icon(Icons.chat_rounded),
            label: const Text('Contactar por WhatsApp'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onUpload,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: AppColors.navy,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.upload_rounded),
            label: const Text('Subir otro comprobante'),
          ),
        ],
      ),
      ChargeStatus.paid => _Panel(
        color: AppColors.success,
        icon: Icons.verified_rounded,
        title: 'Pago aprobado',
        message: c.paidAt == null
            ? 'El club validó tu pago.'
            : 'El club validó tu pago el ${formatDate(c.paidAt!)}.',
        actions: [
          FilledButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SolvencyPage())),
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Ver mi solvencia'),
          ),
        ],
      ),
      ChargeStatus.cancelled => const _Panel(
        color: AppColors.textMuted,
        icon: Icons.block_rounded,
        title: 'Cobro anulado',
        message: 'El club anuló este cobro; no tienes que pagarlo.',
      ),
    };
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
    this.quote,
    this.actions = const [],
  });

  final Color color;
  final IconData icon;
  final String title;
  final String message;
  final String? quote;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppColors.text)),
          if (quote != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border(left: BorderSide(color: color, width: 4)),
              ),
              child: Text(
                quote!,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[const SizedBox(height: 16), ...actions],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: danger ? AppColors.error : AppColors.text,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Datos del comprobante tal como los escribió el padre.
class VoucherDetails extends StatelessWidget {
  const VoucherDetails({super.key, required this.voucher, this.chargeAmount});

  final Voucher voucher;

  /// Si se indica, marca en rojo el monto que no coincide.
  final double? chargeAmount;

  @override
  Widget build(BuildContext context) {
    final v = voucher;
    final mismatch =
        chargeAmount != null &&
        v.amount != null &&
        (v.amount! - chargeAmount!).abs() > 0.001;
    return Column(
      children: [
        if (v.amount != null)
          _InfoRow(
            icon: Icons.payments_outlined,
            label: 'Monto',
            value: mismatch
                ? '${formatMoney(v.amount!)} (cobro: ${formatMoney(chargeAmount!)})'
                : formatMoney(v.amount!),
            danger: mismatch,
          ),
        if (v.bankReference != null)
          _InfoRow(
            icon: Icons.tag_rounded,
            label: 'Boleta',
            value: v.bankReference!,
          ),
        if (v.paymentDate != null)
          _InfoRow(
            icon: Icons.event_available_rounded,
            label: 'Fecha de pago',
            value: formatDate(v.paymentDate!),
          ),
        if (v.description != null)
          _InfoRow(
            icon: Icons.notes_rounded,
            label: 'Descripción',
            value: v.description!,
          ),
        _InfoRow(
          icon: Icons.upload_rounded,
          label: 'Enviado',
          value: formatDateTime(v.uploadedAt),
        ),
        if (v.reviewedAt != null)
          _InfoRow(
            icon: Icons.fact_check_outlined,
            label: 'Revisado',
            value: [formatDateTime(v.reviewedAt!), ?v.reviewedBy].join(' · '),
          ),
      ],
    );
  }
}

/// Subir el comprobante de un cobro: foto (cámara o galería) y los datos
/// del depósito, todos obligatorios. La foto se analiza (EXIF y texto) y se
/// comprime en el teléfono antes de enviarla. Devuelve el cobro actualizado.
class UploadVoucherPage extends StatefulWidget {
  const UploadVoucherPage({super.key, required this.charge});

  final Charge charge;

  @override
  State<UploadVoucherPage> createState() => _UploadVoucherPageState();
}

class _UploadVoucherPageState extends State<UploadVoucherPage> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: moneyText(widget.charge.amount),
  );
  final _reference = TextEditingController();
  final _description = TextEditingController();
  DateTime? _paymentDate;
  XFile? _file;
  Future<VoucherAnalysis>? _analysis;

  /// Etapa del envío; null si no se está enviando.
  VoucherStage? _stage;

  /// Análisis en segundo plano de la foto recién elegida.
  bool _analyzing = false;
  bool _photoMissing = false;

  /// Lo que sugirió el OCR (para avisar al padre).
  bool _referenceSuggested = false;
  List<double> _ocrAmounts = const [];

  bool get _busy => _stage != null;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    XFile? file;
    try {
      // Sin redimensionar: se necesita el original con su EXIF.
      file = await ImagePicker().pickImage(source: source);
    } catch (_) {
      if (mounted) {
        showAppMessage(
          context,
          'No se pudo abrir la cámara o la galería. Revisa los permisos.',
          error: true,
        );
      }
      return;
    }
    if (file != null && mounted) setPhoto(file.path);
  }

  /// Toma la foto elegida y la analiza en segundo plano (OCR y EXIF).
  @visibleForTesting
  void setPhoto(String path) {
    final analysis = VoucherProcessor.instance.analyze(path);
    setState(() {
      _file = XFile(path);
      _photoMissing = false;
      _analysis = analysis;
      _analyzing = true;
      _ocrAmounts = const [];
      if (_referenceSuggested) {
        _reference.clear();
        _referenceSuggested = false;
      }
    });
    unawaited(_applySuggestions(analysis));
  }

  Future<void> _applySuggestions(Future<VoucherAnalysis> future) async {
    VoucherAnalysis a;
    try {
      a = await future;
    } catch (_) {
      if (mounted && _analysis == future) setState(() => _analyzing = false);
      return;
    }
    if (!mounted || _analysis != future) return;
    final s = suggestFromOcr(a.ocrText ?? '');
    setState(() {
      _analyzing = false;
      _ocrAmounts = s.amounts;
      if (_reference.text.trim().isEmpty && s.reference != null) {
        _reference.text = s.reference!;
        _referenceSuggested = true;
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate ?? today,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: today,
      helpText: 'Fecha del depósito o transferencia',
    );
    if (picked != null && mounted) setState(() => _paymentDate = picked);
  }

  Future<void> _send() async {
    final formOk = _formKey.currentState!.validate();
    final file = _file;
    setState(() => _photoMissing = file == null);
    if (!formOk || file == null) {
      showAppMessage(
        context,
        file == null
            ? 'Agrega la foto del comprobante.'
            : 'Revisa los datos marcados en rojo.',
        error: true,
      );
      return;
    }
    final processor = VoucherProcessor.instance;
    try {
      setState(() => _stage = VoucherStage.analyzing);
      VoucherAnalysis analysis;
      try {
        analysis = await (_analysis ?? processor.analyze(file.path));
      } catch (_) {
        analysis = const VoucherAnalysis(); // Sin análisis se sigue.
      }
      if (!mounted) return;
      setState(() => _stage = VoucherStage.compressing);
      final bytes = await processor.compress(file.path, analysis);
      if (!mounted) return;
      setState(() => _stage = VoucherStage.uploading);
      final updated = await PaymentsRepository.instance.uploadVoucher(
        widget.charge.id,
        VoucherForm(
          amount: parseMoney(_amount.text)!,
          bankReference: _reference.text.trim(),
          description: _description.text.trim(),
          paymentDate: _paymentDate!,
        ),
        VoucherUpload(
          bytes: bytes,
          ocrText: analysis.ocrText,
          editSignals: analysis.editSignals,
          previewPath: file.path,
        ),
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showAppMessage(
          context,
          'No se pudo procesar la foto. Intenta con otra.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _stage = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.charge;
    final file = _file;
    final ocrMismatch =
        _ocrAmounts.isNotEmpty &&
        !_ocrAmounts.any((a) => (a - c.amount).abs() < 0.001);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: pageAppBar(context, 'Subir comprobante'),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              ListCard(
                leading: AppAvatar(
                  seed: c.type.code,
                  icon: Icons.receipt_long_rounded,
                ),
                title: c.concept,
                subtitle: [
                  formatMoney(c.amount),
                  if (c.dueDate != null) 'vence el ${formatDate(c.dueDate!)}',
                ].join(' · '),
              ),
              const SizedBox(height: 8),
              _PhotoBox(
                file: file,
                missing: _photoMissing,
                onTap: _busy ? null : _pick,
              ),
              if (_analyzing && !_busy) ...[
                const SizedBox(height: 8),
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.navy,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Leyendo el comprobante…',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
              if (ocrMismatch) ...[
                const SizedBox(height: 10),
                _Hint(
                  icon: Icons.info_outline_rounded,
                  color: const Color(0xFFB45309),
                  text:
                      'En la foto vemos ${_ocrAmounts.map(formatMoney).join(', ')}. '
                      'El comprobante debe ser por ${formatMoney(c.amount)}.',
                ),
              ],
              const SizedBox(height: 20),
              MoneyField(
                label: 'Monto pagado',
                controller: _amount,
                enabled: !_busy,
                extraValidator: (a) => (a - c.amount).abs() > 0.001
                    ? 'Debe ser igual al cobro (${formatMoney(c.amount)})'
                    : null,
              ),
              const SizedBox(height: 16),
              AuthField(
                label: 'Número de boleta o transferencia',
                hint: 'Ej. 889231',
                icon: Icons.tag_rounded,
                controller: _reference,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                  LengthLimitingTextInputFormatter(60),
                ],
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Escribe el número de boleta';
                  if (t.length < 4) return 'Mínimo 4 caracteres';
                  if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(t)) {
                    return 'Solo letras, números y guiones';
                  }
                  return null;
                },
              ),
              if (_referenceSuggested)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Lo leímos de la foto: verifica que sea correcto.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 16),
              AuthField(
                label: 'Descripción',
                hint: 'Ej. Depósito Banrural ${c.concept.toLowerCase()}',
                icon: Icons.notes_rounded,
                controller: _description,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(250)],
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Escribe una descripción';
                  if (t.length < 5) return 'Mínimo 5 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _DateField(value: _paymentDate, onTap: _busy ? null : _pickDate),
              const SizedBox(height: 24),
              if (_busy)
                _ProgressSteps(stage: _stage!)
              else
                LoadingButton(
                  label: 'Enviar comprobante',
                  loading: false,
                  onPressed: _send,
                ),
              const SizedBox(height: 10),
              const Text(
                'Quedará en revisión hasta que un administrador lo valide. '
                'Si lo subes a más tardar el día de vencimiento, cuenta como '
                'pagado a tiempo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({
    required this.file,
    required this.missing,
    required this.onTap,
  });

  final XFile? file;
  final bool missing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = file;
    final borderColor = missing
        ? AppColors.error
        : f == null
        ? AppColors.navy
        : AppColors.border;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            height: 260,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: borderColor,
                width: f == null ? 1.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: f == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        size: 44,
                        color: missing ? AppColors.error : AppColors.navy,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Toca para agregar la foto del comprobante',
                        style: TextStyle(
                          color: missing ? AppColors.error : AppColors.navy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Que se lean el monto, la fecha y el número.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(f.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: AppColors.textMuted,
                            size: 40,
                          ),
                        ),
                      ),
                      const Positioned(
                        right: 10,
                        bottom: 10,
                        child: Pill(
                          'Cambiar foto',
                          filled: true,
                          tone: PillTone.brand,
                          icon: Icons.refresh_rounded,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (missing)
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'La foto del comprobante es obligatoria',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Fecha de pago: obligatoria y no futura (el selector no deja elegirla).
class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onTap});

  final DateTime? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      validator: (_) => value == null ? 'Elige la fecha de pago' : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fecha de pago',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap == null
                ? null
                : () {
                    onTap!();
                    state.didChange(value);
                  },
            child: InputDecorator(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.event_rounded, size: 20),
                suffixIcon: const Icon(Icons.expand_more_rounded),
                errorText: state.hasError && value == null
                    ? state.errorText
                    : null,
              ),
              child: Text(
                value == null ? 'Selecciona la fecha' : formatDate(value!),
                style: TextStyle(
                  color: value == null ? AppColors.textMuted : AppColors.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
        ),
      ],
    ),
  );
}

/// Analizando → comprimiendo → subiendo, con la etapa actual resaltada.
class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps({required this.stage});

  final VoucherStage stage;

  @override
  Widget build(BuildContext context) {
    const steps = VoucherStage.values;
    final current = steps.indexOf(stage);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, s) in steps.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        i < current
                            ? Icons.check_circle_rounded
                            : switch (s) {
                                VoucherStage.analyzing =>
                                  Icons.document_scanner_outlined,
                                VoucherStage.compressing =>
                                  Icons.compress_rounded,
                                VoucherStage.uploading =>
                                  Icons.cloud_upload_outlined,
                              },
                        color: i <= current
                            ? (i < current ? AppColors.success : AppColors.navy)
                            : AppColors.textMuted,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        switch (s) {
                          VoucherStage.analyzing => 'Analizando',
                          VoucherStage.compressing => 'Comprimiendo',
                          VoucherStage.uploading => 'Subiendo',
                        },
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: i == current ? FontWeight.w700 : null,
                          color: i <= current
                              ? AppColors.text
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: stage == VoucherStage.uploading ? null : (current + 1) / 4,
              minHeight: 6,
              color: AppColors.navy,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            stage.label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
