import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/format/formats.dart';
import '../../../core/widgets/app_ui.dart';
import '../../family/data/dependent.dart';
import '../../family/data/dependent_repository.dart';
import '../data/payment_models.dart';
import '../data/payments_repository.dart';
import 'charge_detail_page.dart';
import 'charge_widgets.dart';

/// Solvencia del padre: estado general, el de cada hijo y los pagos
/// aprobados por el club.
class SolvencyPage extends StatefulWidget {
  const SolvencyPage({super.key});

  @override
  State<SolvencyPage> createState() => _SolvencyPageState();
}

class _SolvencyPageState extends State<SolvencyPage> {
  Balance? _balance;
  List<Dependent> _kids = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final kidsFuture = DependentRepository.instance.list();
      final charges = await PaymentsRepository.instance.myCharges();
      final kids = await kidsFuture;
      if (mounted) {
        setState(() {
          _balance = Balance(charges);
          _kids = kids;
        });
      }
    } on PaymentsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on DependentException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _balance;
    final paid = [...?b?.paid]
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
              _Seal(balance: b),
              const SizedBox(height: 18),
              if (_kids.isNotEmpty) ...[
                ListHeader('Por hijo', count: _kids.length),
                for (final k in _kids)
                  ListCard(
                    leading: AppAvatar(seed: k.cui, initials: k.initials),
                    title: k.fullName,
                    subtitle: b.solventFor(k.id)
                        ? 'Sin pagos pendientes'
                        : 'Debe ${formatMoney(b.owedBy(k.id))}',
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: b.solventFor(k.id)
                          ? const Pill(
                              'Solvente',
                              tone: PillTone.success,
                              icon: Icons.verified_rounded,
                            )
                          : const Pill(
                              'Pendiente',
                              tone: PillTone.warning,
                              icon: Icons.schedule_rounded,
                            ),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
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

/// Sello grande: verde si está solvente, ámbar si debe algo.
class _Seal extends StatelessWidget {
  const _Seal({required this.balance});
  final Balance balance;

  @override
  Widget build(BuildContext context) {
    final ok = balance.solvent;
    final color = ok ? AppColors.success : const Color(0xFFB45309);
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
              ok ? Icons.workspace_premium_rounded : Icons.pending_actions,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            ok ? 'Solvente' : 'Con pagos pendientes',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ok
                ? 'Estás al día con el club al ${formatDate(DateTime.now())}.'
                : 'Debes ${formatMoney(balance.totalOwed)} en '
                      '${balance.open.length} '
                      '${balance.open.length == 1 ? 'cobro' : 'cobros'}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
          ),
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
    List<Charge> by(ChargeStatus s) => [...all.where((c) => c.status == s)];
    final groups = [
      ('Rechazados', by(ChargeStatus.rejected)),
      ('Por pagar', by(ChargeStatus.pending)),
      ('En revisión', by(ChargeStatus.inReview)),
      ('Pagados', by(ChargeStatus.paid)),
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
            message: 'Cuando el club te asigne un pago aparecerá aquí.',
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
