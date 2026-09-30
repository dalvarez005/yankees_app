import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../../core/format/formats.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/money_field.dart';
import '../../auth/data/app_user.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../../payments/data/payment_models.dart';
import '../../payments/data/payments_repository.dart';
import '../../payments/data/settings_repository.dart';
import '../data/billing_models.dart';
import '../data/billing_repository.dart';

/// Usuarios recién registrados esperando validación (`usuarios.validar`),
/// los más antiguos primero.
class PendingUsersPage extends StatefulWidget {
  const PendingUsersPage({super.key, required this.user, this.openUserId});

  final AppUser user;

  /// Abre directo el detalle de ese usuario (desde una notificación).
  final String? openUserId;

  @override
  State<PendingUsersPage> createState() => _PendingUsersPageState();
}

class _PendingUsersPageState extends State<PendingUsersPage> {
  final _search = TextEditingController();
  List<PendingUser>? _users;
  String? _error;
  late String? _autoOpen = widget.openUserId;

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
      final users = await BillingRepository.instance.pendingUsers(
        search: _search.text,
      );
      if (!mounted) return;
      setState(() => _users = users);
      final target = users.where((u) => u.id == _autoOpen).firstOrNull;
      _autoOpen = null;
      if (target != null) await _open(target);
    } on BillingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open(PendingUser u) async {
    final validated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ValidateUserPage(pending: u)),
    );
    if (validated == true && mounted) {
      showAppMessage(
        context,
        '${u.name} fue validado. Ya puede usar la app y se creó su '
        'cobro de inscripción.',
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.usersValidate)) {
      return const NoAccessView();
    }
    final users = _users;
    return Scaffold(
      appBar: pageAppBar(context, 'Usuarios por validar'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o correo',
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: AsyncListView(
                loading: users == null,
                error: _error,
                onRetry: _load,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                header: users == null || users.isEmpty
                    ? null
                    : ListHeader('Esperando validación', count: users.length),
                empty: const EmptyState(
                  icon: Icons.how_to_reg_rounded,
                  title: 'Nadie esperando',
                  message: 'Cuando alguien se registre aparecerá aquí.',
                ),
                children: [
                  for (final u in users ?? const <PendingUser>[])
                    ListCard(
                      onTap: () => _open(u),
                      leading: AppAvatar(seed: u.email, initials: _initials(u)),
                      title: u.name,
                      subtitle: u.email,
                      footer: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (u.createdAt != null)
                            Pill(
                              'Desde ${formatDate(u.createdAt!)}',
                              icon: Icons.schedule_rounded,
                              tone: PillTone.warning,
                            ),
                          Pill(
                            u.dependentsCount == 1
                                ? '1 hijo'
                                : '${u.dependentsCount} hijos',
                            icon: Icons.child_care_rounded,
                            tone: PillTone.brand,
                          ),
                        ],
                      ),
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

String _initials(PendingUser u) => u.name
    .split(RegExp(r'[\s.@_-]+'))
    .where((p) => p.isNotEmpty)
    .take(2)
    .map((p) => p[0].toUpperCase())
    .join();

/// Validar a un usuario: inscripción y mensualidad (sugeridas con la
/// configuración). Devuelve true si se validó.
class ValidateUserPage extends StatefulWidget {
  const ValidateUserPage({super.key, required this.pending});

  final PendingUser pending;

  @override
  State<ValidateUserPage> createState() => _ValidateUserPageState();
}

class _ValidateUserPageState extends State<ValidateUserPage> {
  final _formKey = GlobalKey<FormState>();
  final _enrollment = TextEditingController();
  final _monthly = TextEditingController();
  PaymentSettings? _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  @override
  void dispose() {
    _enrollment.dispose();
    _monthly.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    try {
      final s = await SettingsRepository.instance.paymentSettings();
      if (!mounted) return;
      setState(() => _settings = s);
      // Solo si el admin no escribió nada todavía.
      if (_enrollment.text.isEmpty && s.defaultEnrollmentFee > 0) {
        _enrollment.text = moneyText(s.defaultEnrollmentFee);
      }
      if (_monthly.text.isEmpty && s.defaultMonthlyFee > 0) {
        _monthly.text = moneyText(s.defaultMonthlyFee);
      }
    } on PaymentsException {
      // Sin sugerencias: el admin escribe los montos.
    }
  }

  Future<void> _validate() async {
    if (!_formKey.currentState!.validate()) return;
    final u = widget.pending;
    final enrollment = parseMoney(_enrollment.text)!;
    final monthly = parseMoney(_monthly.text)!;
    final ok = await confirmAction(
      context,
      title: '¿Validar a ${u.name}?',
      message:
          'Se creará su cobro de inscripción por ${formatMoney(enrollment)} '
          'y desde el próximo mes su mensualidad de ${formatMoney(monthly)}.',
      confirmLabel: 'Validar',
      destructive: false,
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await BillingRepository.instance.validateUser(
        u.id,
        enrollmentFee: enrollment,
        monthlyFee: monthly,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on BillingException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.pending;
    final due = _settings?.dueDay ?? 15;
    return Scaffold(
      appBar: pageAppBar(context, 'Validar usuario'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            ListCard(
              leading: AppAvatar(seed: u.email, initials: _initials(u)),
              title: u.name,
              subtitle: u.email,
              footer: Text(
                [
                  if (u.createdAt != null)
                    'Registrado el ${formatDate(u.createdAt!)}',
                  u.dependentsCount == 1
                      ? '1 hijo registrado'
                      : '${u.dependentsCount} hijos registrados',
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const ListHeader('Cuotas'),
            MoneyField(label: 'Inscripción', controller: _enrollment),
            const SizedBox(height: 16),
            MoneyField(label: 'Mensualidad', controller: _monthly),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.navy,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'La inscripción se cobra de inmediato y vence en $due '
                      'días. La primera mensualidad se genera el día 1 del '
                      'mes siguiente y vence el día $due.',
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Validar usuario',
              loading: _saving,
              onPressed: _validate,
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuotas de un usuario en la hoja de Usuarios (`usuarios.validar`):
/// ver y editar; si está pendiente, ir a validarlo.
class UserFeesSection extends StatefulWidget {
  const UserFeesSection({
    super.key,
    required this.userId,
    required this.name,
    required this.email,
  });

  final String userId;
  final String name;
  final String email;

  @override
  State<UserFeesSection> createState() => _UserFeesSectionState();
}

class _UserFeesSectionState extends State<UserFeesSection> {
  final _formKey = GlobalKey<FormState>();
  final _enrollment = TextEditingController();
  final _monthly = TextEditingController();
  Billing? _billing;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _enrollment.dispose();
    _monthly.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final b = await BillingRepository.instance.userBilling(widget.userId);
      if (!mounted) return;
      _enrollment.text = moneyText(b.enrollmentFee);
      _monthly.text = moneyText(b.monthlyFee);
      setState(() => _billing = b);
    } on BillingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    final b = _billing;
    if (b == null || !_formKey.currentState!.validate()) return;
    final enrollment = parseMoney(_enrollment.text)!;
    final monthly = parseMoney(_monthly.text)!;
    // Solo se manda lo que cambió.
    final newEnrollment = enrollment != b.enrollmentFee ? enrollment : null;
    final newMonthly = monthly != b.monthlyFee ? monthly : null;
    if (newEnrollment == null && newMonthly == null) {
      showAppMessage(context, 'No hay cambios para guardar.', info: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await BillingRepository.instance.updateUserFees(
        widget.userId,
        enrollmentFee: newEnrollment,
        monthlyFee: newMonthly,
      );
      if (!mounted) return;
      setState(() => _billing = updated);
      showAppMessage(context, 'Cuotas actualizadas.');
    } on BillingException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _validate() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ValidateUserPage(
          pending: PendingUser(
            id: widget.userId,
            email: widget.email,
            firstName: widget.name,
            firstLastName: '',
          ),
        ),
      ),
    );
    if (done == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = _billing;
    final Widget body;
    if (_error != null) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ],
      );
    } else if (b == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(color: AppColors.navy)),
      );
    } else if (b.status == BillingStatus.notApplicable) {
      body = const Text(
        'No aplica: es administrador y no se le cobran cuotas.',
        style: TextStyle(color: AppColors.textMuted),
      );
    } else if (b.status == BillingStatus.pending) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Todavía no está validado: no puede usar la app ni se le cobra.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _validate,
            icon: const Icon(Icons.how_to_reg_rounded),
            label: const Text('Validar y definir cuotas'),
          ),
        ],
      );
    } else {
      body = Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                b.solvent
                    ? const Pill(
                        'Solvente',
                        tone: PillTone.success,
                        icon: Icons.verified_rounded,
                      )
                    : Pill(
                        'Insolvente · ${formatMoney(b.overdueAmount)}',
                        tone: PillTone.danger,
                        icon: Icons.warning_amber_rounded,
                      ),
                if (b.approvedBy != null)
                  Pill('Validó ${b.approvedBy}', icon: Icons.how_to_reg),
              ],
            ),
            const SizedBox(height: 14),
            MoneyField(label: 'Inscripción', controller: _enrollment),
            const SizedBox(height: 14),
            MoneyField(label: 'Mensualidad', controller: _monthly),
            const SizedBox(height: 10),
            const Text(
              'La mensualidad nueva aplica desde el próximo período; los '
              'cobros ya generados no cambian. La inscripción solo se puede '
              'cambiar si aún no se pagó ni está en revisión.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            LoadingButton(
              label: 'Guardar cuotas',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const ListHeader('Cuotas'), body],
    );
  }
}
