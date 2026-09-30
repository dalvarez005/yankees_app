import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/format/formats.dart';
import '../../../core/widgets/app_ui.dart';
import '../data/payment_models.dart';

/// Colores e íconos de cada estado, iguales en todas las pantallas.
({String label, PillTone tone, IconData icon}) chargeStatusStyle(Charge c) =>
    switch (c.status) {
      ChargeStatus.pending when c.overdue => (
        label: 'Vencido',
        tone: PillTone.danger,
        icon: Icons.schedule_rounded,
      ),
      ChargeStatus.pending => (
        label: 'Por pagar',
        tone: PillTone.warning,
        icon: Icons.schedule_rounded,
      ),
      ChargeStatus.inReview => (
        label: 'En revisión',
        tone: PillTone.brand,
        icon: Icons.hourglass_top_rounded,
      ),
      ChargeStatus.rejected => (
        label: 'Rechazado',
        tone: PillTone.danger,
        icon: Icons.cancel_outlined,
      ),
      ChargeStatus.paid => (
        label: 'Pagado',
        tone: PillTone.success,
        icon: Icons.check_circle_outline_rounded,
      ),
      ChargeStatus.cancelled => (
        label: 'Anulado',
        tone: PillTone.neutral,
        icon: Icons.block_rounded,
      ),
    };

class ChargeStatusPill extends StatelessWidget {
  const ChargeStatusPill(this.charge, {super.key});
  final Charge charge;

  @override
  Widget build(BuildContext context) {
    final s = chargeStatusStyle(charge);
    return Pill(s.label, tone: s.tone, icon: s.icon);
  }
}

/// Fila de un cobro: concepto, hijo, vencimiento, monto y estado.
class ChargeCard extends StatelessWidget {
  const ChargeCard({
    super.key,
    required this.charge,
    this.onTap,
    this.showParent = false,
    this.trailing,
  });

  final Charge charge;
  final VoidCallback? onTap;

  /// Vista de admin: muestra a qué padre se le cobra.
  final bool showParent;
  final Widget? trailing;

  String get _detail {
    final c = charge;
    final who = showParent && c.parentName != null
        ? '${c.dependentName} · ${c.parentName}'
        : c.dependentName;
    if (c.status == ChargeStatus.paid && c.paidAt != null) {
      return '$who · pagado el ${formatDate(c.paidAt!)}';
    }
    if (c.status == ChargeStatus.inReview && c.voucher != null) {
      return '$who · enviado el ${formatDate(c.voucher!.uploadedAt)}';
    }
    if (c.dueDate != null && c.status.owes) {
      final days = daysUntil(c.dueDate!);
      final when = days < 0
          ? 'venció el ${formatDate(c.dueDate!)}'
          : days == 0
          ? 'vence hoy'
          : days == 1
          ? 'vence mañana'
          : 'vence el ${formatDate(c.dueDate!)}';
      return '$who · $when';
    }
    return who;
  }

  @override
  Widget build(BuildContext context) {
    final c = charge;
    final style = chargeStatusStyle(c);
    final muted = c.status == ChargeStatus.cancelled;
    return ListCard(
      onTap: onTap,
      dimmed: muted,
      leading: AppAvatar(
        seed: c.concept,
        icon: switch (c.status) {
          ChargeStatus.paid => Icons.verified_rounded,
          ChargeStatus.inReview => Icons.hourglass_top_rounded,
          ChargeStatus.rejected => Icons.report_gmailerrorred_rounded,
          _ => Icons.receipt_long_rounded,
        },
        muted: muted,
      ),
      title: c.concept,
      subtitle: _detail,
      footer: Row(
        children: [
          Pill(style.label, tone: style.tone, icon: style.icon),
          const Spacer(),
          Text(
            formatMoney(c.amount),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: muted
                  ? AppColors.textMuted
                  : c.status == ChargeStatus.paid
                  ? AppColors.success
                  : AppColors.text,
              decoration: muted ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
      trailing: trailing,
    );
  }
}

/// Resumen del saldo sobre la cabecera azul del padre.
class BalanceHeaderCard extends StatelessWidget {
  const BalanceHeaderCard({
    super.key,
    required this.balance,
    required this.onTap,
  });

  /// null mientras carga.
  final Balance? balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = balance;
    final solvent = b?.solvent ?? false;
    final inReview = b?.totalInReview ?? 0;
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: b == null ? null : onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: solvent
                      ? AppColors.success
                      : Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  solvent
                      ? Icons.verified_rounded
                      : Icons.account_balance_wallet_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b == null
                          ? 'Consultando tu saldo…'
                          : solvent
                          ? 'Estás al día'
                          : 'Saldo pendiente',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      b == null
                          ? '—'
                          : solvent
                          ? 'Solvente'
                          : formatMoney(b.totalOwed),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if (inReview > 0)
                      Text(
                        '${formatMoney(inReview)} en revisión',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                solvent ? 'Ver solvencia' : 'Ver pagos',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
