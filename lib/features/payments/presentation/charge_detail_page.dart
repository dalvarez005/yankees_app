import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_colors.dart';
import '../../../core/contact/whatsapp.dart';
import '../../../core/format/formats.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/presentation/widgets/auth_field.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../data/payment_models.dart';
import '../data/payments_repository.dart';
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
    PaymentContact contact;
    try {
      contact = await PaymentsRepository.instance.contact();
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
      return;
    }
    if (!contact.configured) {
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
          '(${formatMoney(c.amount)}) de ${c.dependentName}. '
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
              const ListHeader('Comprobante enviado'),
              VoucherImage(voucher: c.voucher!),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.upload_rounded,
                label: 'Enviado',
                value: formatDateTime(c.voucher!.uploadedAt),
              ),
              if (c.voucher!.reference != null)
                _InfoRow(
                  icon: Icons.tag_rounded,
                  label: 'Referencia',
                  value: c.voucher!.reference!,
                ),
              if (c.voucher!.reviewedAt != null)
                _InfoRow(
                  icon: Icons.fact_check_outlined,
                  label: 'Revisado',
                  value: formatDateTime(c.voucher!.reviewedAt!),
                ),
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
          if (c.description != null) ...[
            const SizedBox(height: 6),
            Text(
              c.description!,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
          const Divider(height: 28, color: AppColors.border),
          _InfoRow(
            icon: Icons.child_care_rounded,
            label: 'Hijo',
            value: [c.dependentName, ?c.categoryName].join(' · '),
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
            label: 'Asignado',
            value: formatDate(c.createdAt),
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
        message:
            'Paga en el banco o por transferencia y sube la foto del '
            'comprobante. El club lo validará.',
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
            'revisará y te avisaremos aquí el resultado.',
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

/// Elegir la foto del comprobante (cámara o galería), revisar y enviar.
/// Devuelve el cobro actualizado.
class UploadVoucherPage extends StatefulWidget {
  const UploadVoucherPage({super.key, required this.charge});

  final Charge charge;

  @override
  State<UploadVoucherPage> createState() => _UploadVoucherPageState();
}

class _UploadVoucherPageState extends State<UploadVoucherPage> {
  final _reference = TextEditingController();
  XFile? _file;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _reference.dispose();
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
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (file != null && mounted) setState(() => _file = file);
    } catch (_) {
      if (mounted) {
        showAppMessage(
          context,
          'No se pudo abrir la cámara o la galería. Revisa los permisos.',
          error: true,
        );
      }
    }
  }

  Future<void> _send() async {
    final file = _file;
    if (file == null) return;
    setState(() => _sending = true);
    try {
      final updated = await PaymentsRepository.instance.uploadVoucher(
        widget.charge.id,
        filePath: file.path,
        reference: _reference.text,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.charge;
    final file = _file;
    return Scaffold(
      appBar: pageAppBar(context, 'Subir comprobante'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          ListCard(
            leading: AppAvatar(seed: c.concept, icon: Icons.receipt_long),
            title: c.concept,
            subtitle: '${c.dependentName} · ${formatMoney(c.amount)}',
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _sending ? null : _pick,
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: file == null ? AppColors.navy : AppColors.border,
                  width: file == null ? 1.5 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: file == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          size: 44,
                          color: AppColors.navy,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Toca para agregar la foto del comprobante',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Que se lean el monto, la fecha y el número.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(file.path), fit: BoxFit.cover),
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
          const SizedBox(height: 18),
          AuthField(
            label: 'Número de boleta o transferencia (opcional)',
            hint: 'Ej. 889231',
            icon: Icons.tag_rounded,
            controller: _reference,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 24),
          LoadingButton(
            label: 'Enviar comprobante',
            loading: _sending,
            onPressed: file == null ? null : _send,
          ),
          const SizedBox(height: 10),
          const Text(
            'Quedará pendiente hasta que un administrador lo valide.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
