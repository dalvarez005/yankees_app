import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../../core/format/formats.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/app_user.dart';
import '../../billing/presentation/pending_users_page.dart';
import '../../payments/data/payments_repository.dart';
import '../../payments/presentation/admin/review_payments_page.dart';
import '../../payments/presentation/charge_detail_page.dart';
import '../../payments/presentation/solvency_page.dart';
import '../data/notification_repository.dart';

/// Campana con el número de notificaciones sin leer, para las cabeceras
/// de marca (fondo azul). Al volver de la lista se actualiza el número.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, required this.user, this.onChanged});

  final AppUser user;

  /// Al volver de la lista (algo pudo cambiar: p. ej. se validó un pago).
  final VoidCallback? onChanged;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await NotificationRepository.instance.myNotifications(
        unreadOnly: true,
      );
      if (mounted) setState(() => _unread = page.unreadCount);
    } on NotificationException {
      // Sin contador: la campana igual abre la lista.
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NotificationsPage(user: widget.user)),
    );
    if (!mounted) return;
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _unread > 0
          ? 'Notificaciones ($_unread sin leer)'
          : 'Notificaciones',
      onPressed: _open,
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        backgroundColor: AppColors.error,
        child: const Icon(
          Icons.notifications_none_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }
}

/// Notificaciones del usuario, las más recientes primero. Tocar una la
/// marca como leída y lleva a la pantalla relacionada si aplica.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.user});

  final AppUser user;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<AppNotification>? _items;
  int _unread = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await NotificationRepository.instance.myNotifications();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _unread = page.unreadCount;
      });
    } on NotificationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _markAll() async {
    try {
      final unread = await NotificationRepository.instance.markAsRead(
        all: true,
      );
      final now = DateTime.now();
      if (!mounted) return;
      setState(() {
        _unread = unread;
        _items = [for (final n in _items ?? const []) n.markedRead(now)];
      });
    } on NotificationException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (n.unread) {
      try {
        final unread = await NotificationRepository.instance.markAsRead(
          ids: [n.id],
        );
        final now = DateTime.now();
        if (mounted) {
          setState(() {
            _unread = unread;
            _items = [
              for (final x in _items ?? const <AppNotification>[])
                x.id == n.id ? x.markedRead(now) : x,
            ];
          });
        }
      } on NotificationException {
        // Se abre igual.
      }
    }
    if (!mounted) return;
    final page = await _target(n);
    if (page != null && mounted) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  /// Pantalla relacionada, según el tipo y los permisos del usuario.
  Future<Widget?> _target(AppNotification n) async {
    final u = widget.user;
    final chargeId = n.data['chargeId']?.toString();
    switch (n.type) {
      case NotificationTypes.userPendingValidation
          when u.can(Permissions.usersValidate):
        return PendingUsersPage(
          user: u,
          openUserId: n.data['userId']?.toString(),
        );
      case NotificationTypes.voucherSubmitted
          when u.can(Permissions.paymentsReview):
        return ReviewPaymentsPage(user: u, openChargeId: chargeId);
      case NotificationTypes.voucherApproved ||
              NotificationTypes.voucherRejected ||
              NotificationTypes.chargeCreated
          when u.can(Permissions.ownDependents):
        if (chargeId != null) {
          try {
            final charges = await PaymentsRepository.instance.myCharges();
            final c = charges.where((c) => c.id == chargeId).firstOrNull;
            if (c != null) return ChargeDetailPage(charge: c);
          } on PaymentsException catch (e) {
            if (mounted) showAppMessage(context, e.message, error: true);
            return null;
          }
        }
        return const MyPaymentsPage();
      case NotificationTypes.paymentReminder
          when u.can(Permissions.ownDependents):
        return const MyPaymentsPage();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: pageAppBar(
        context,
        'Notificaciones',
        actions: [
          if (_unread > 0)
            TextButton(
              onPressed: _markAll,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Marcar leídas'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.navy,
        child: AsyncListView(
          loading: items == null,
          error: _error,
          onRetry: _load,
          empty: const EmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'Sin notificaciones',
            message: 'Aquí verás avisos de pagos, cobros y tu cuenta.',
          ),
          children: [
            for (final n in items ?? const <AppNotification>[])
              _NotificationTile(notification: n, onTap: () => _open(n)),
          ],
        ),
      ),
    );
  }
}

({IconData icon, Color color}) _style(String type) => switch (type) {
  NotificationTypes.userPendingValidation => (
    icon: Icons.person_add_alt_1_rounded,
    color: const Color(0xFF0369A1),
  ),
  NotificationTypes.userValidated => (
    icon: Icons.verified_user_rounded,
    color: AppColors.success,
  ),
  NotificationTypes.chargeCreated => (
    icon: Icons.receipt_long_rounded,
    color: AppColors.navy,
  ),
  NotificationTypes.voucherSubmitted => (
    icon: Icons.fact_check_rounded,
    color: const Color(0xFF15803D),
  ),
  NotificationTypes.voucherApproved => (
    icon: Icons.check_circle_rounded,
    color: AppColors.success,
  ),
  NotificationTypes.voucherRejected => (
    icon: Icons.report_gmailerrorred_rounded,
    color: AppColors.error,
  ),
  NotificationTypes.paymentReminder => (
    icon: Icons.alarm_rounded,
    color: const Color(0xFFB45309),
  ),
  _ => (icon: Icons.notifications_rounded, color: AppColors.navy),
};

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final s = _style(n.type);
    return ListCard(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: s.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(s.icon, color: s.color),
      ),
      title: n.title.isEmpty ? 'Aviso del club' : n.title,
      subtitle: n.body,
      subtitleLines: 3,
      footer: Row(
        children: [
          Text(
            formatDateTime(n.createdAt),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const Spacer(),
          if (n.unread) const Pill('Nueva', tone: PillTone.danger),
        ],
      ),
    );
  }
}
