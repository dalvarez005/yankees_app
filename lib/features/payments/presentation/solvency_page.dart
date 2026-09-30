import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/format/formats.dart';
import '../../../core/widgets/app_ui.dart';
import '../data/payment_models.dart';
import '../data/payments_repository.dart';
import 'charge_detail_page.dart';
import 'charge_widgets.dart';

/// Solvencia del padre: estado general y los pagos aprobados por el club.
class SolvencyPage extends StatefulWidget {
  const SolvencyPage({super.key});

  @override
  State<SolvencyPage> createState() => _SolvencyPageState();
}

class _SolvencyPageState extends State<SolvencyPage> {
  AccountBalance? _balance;
  List<Charge> _charges = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repo = PaymentsRepository.instance;
      final chargesFuture = repo.myCharges();
      final balance = await repo.myBalance();
      final charges = await chargesFuture;
      if (mounted) {
        setState(() {
          _balance = balance;
          _charges = charges;
        });
      }
    } on PaymentsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _balance;
    final paid = [..._charges.where((c) => c.status == ChargeStatus.paid)]
      ..sort(
        (x, y) => (y.paidAt ?? y.createdAt).compareTo(x.paidAt ?? x.createdAt),
      );
    return Scaffold(
      appBar: pageAppBar(context, 'Mi solvencia'),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: AsyncListView(
          loading: b == null,
          error: _error,
          onRetry: _load,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (b != null) ...[
              SolvencySeal(balance: b),
              const SizedBox(height: 18),
              ListHeader('Pagos aprobados', count: paid.length),
              if (paid.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Todavía no hay pagos aprobados',
                  message:
                      'Cuando el club valide un comprobante aparecerá aquí.',
                )
              else
                for (final c in paid)
                  ChargeCard(
                    charge: c,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChargeDetailPage(charge: c),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sello grande: verde si está solvente, rojo si es insolvente.
class SolvencySeal extends StatelessWidget {
  const SolvencySeal({super.key, required this.balance});
  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final b = balance;
    final ok = b.solvent;
    final color = ok ? AppColors.success : AppColors.error;
    final String message;
    if (!ok) {
      message =
          'Tienes ${formatMoney(b.overdueAmount)} vencido. Paga y sube el '
          'comprobante para volver a estar solvente.';
    } else if (b.totalOwed > 0) {
      message =
          'Estás al día. Tienes ${formatMoney(b.totalOwed)} por pagar'
          '${b.nextDueDate == null ? '' : ' antes del ${formatDate(b.nextDueDate!)}'}.';
    } else {
      message = 'Estás al día con el club al ${formatDate(DateTime.now())}.';
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.25)!],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: Icon(
              ok ? Icons.workspace_premium_rounded : Icons.warning_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            ok ? 'Solvente' : 'INSOLVENTE',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
          ),
          if (b.inReviewAmount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${formatMoney(b.inReviewAmount)} en revisión',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Todos los cobros del padre, agrupados por lo que tiene que hacer.
class MyPaymentsPage extends StatefulWidget {
  const MyPaymentsPage({super.key});

  @override
  State<MyPaymentsPage> createState() => _MyPaymentsPageState();
}

class _MyPaymentsPageState extends State<MyPaymentsPage> {
  List<Charge>? _charges;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final charges = await PaymentsRepository.instance.myCharges();
      if (mounted) setState(() => _charges = charges);
    } on PaymentsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open(Charge c) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ChargeDetailPage(charge: c)),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final all = _charges ?? const <Charge>[];
    List<Charge> by(bool Function(Charge) test) => [...all.where(test)];
    final groups = [
      ('Vencidos', by((c) => c.status.canUpload && c.overdue)),
      (
        'Rechazados',
        by((c) => c.status == ChargeStatus.rejected && !c.overdue),
      ),
      ('Por pagar', by((c) => c.status == ChargeStatus.pending && !c.overdue)),
      ('En revisión', by((c) => c.status == ChargeStatus.inReview)),
      ('Pagados', by((c) => c.status == ChargeStatus.paid)),
    ];
    return Scaffold(
      appBar: pageAppBar(
        context,
        'Mis pagos',
        actions: [
          IconButton(
            tooltip: 'Mi solvencia',
            icon: const Icon(Icons.workspace_premium_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SolvencyPage())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: AsyncListView(
          loading: _charges == null,
          error: _error,
          onRetry: _load,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          empty: const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No tienes cobros',
            message:
                'Tu inscripción y tus mensualidades aparecerán aquí cuando '
                'el club las genere.',
          ),
          children: [
            for (final (label, items) in groups)
              if (items.isNotEmpty) ...[
                ListHeader(label, count: items.length),
                for (final c in items)
                  ChargeCard(charge: c, onTap: () => _open(c)),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}
