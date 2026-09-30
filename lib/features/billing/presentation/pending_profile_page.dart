import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../app/routes.dart';
import '../../../core/contact/whatsapp.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/data/app_user.dart';
import '../../auth/data/auth_repository.dart';
import '../../payments/data/payment_models.dart';
import '../../payments/data/payments_repository.dart';
import '../../payments/data/settings_repository.dart';

/// Padre recién registrado que el club aún no valida (perfil de cobro
/// `P`). No puede avanzar hasta que un administrador defina sus cuotas.
class PendingProfilePage extends StatefulWidget {
  const PendingProfilePage({super.key, required this.user});

  final AppUser user;

  @override
  State<PendingProfilePage> createState() => _PendingProfilePageState();
}

class _PendingProfilePageState extends State<PendingProfilePage> {
  PaymentSettings? _settings;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  /// Si falla, simplemente no se muestra el botón de WhatsApp.
  Future<void> _loadContact() async {
    try {
      final s = await SettingsRepository.instance.paymentSettings();
      if (mounted) setState(() => _settings = s);
    } on PaymentsException {
      // Sin contacto.
    }
  }

  /// Vuelve a pedir `/me`: si ya lo validaron, entra al inicio.
  Future<void> _refresh() async {
    setState(() => _checking = true);
    try {
      final user = await AuthRepository.instance.fetchProfile();
      if (!mounted) return;
      if (user.awaitingValidation) {
        showAppMessage(
          context,
          'Tu perfil todavía está en configuración. Te avisaremos cuando '
          'esté listo.',
          info: true,
        );
      } else {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(Routes.home, (_) => false, arguments: user);
      }
    } on AuthException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _whatsApp() async {
    final s = _settings;
    if (s == null || !s.hasContact) return;
    final ok = await openWhatsApp(
      s.whatsappNumber,
      message:
          'Hola, soy ${widget.user.displayName} (${widget.user.email}). Me '
          'registré en la app del Club Yankees y estoy esperando la '
          'validación de mi perfil.',
    );
    if (!ok && mounted) {
      showAppMessage(context, 'No se pudo abrir WhatsApp.', error: true);
    }
  }

  Future<void> _signOut() async {
    await AuthRepository.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final contact = _settings;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            BrandHeader(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 64),
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.manage_accounts_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Estamos configurando tu perfil',
                        textAlign: TextAlign.center,
                        style: text.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Hola, ${widget.user.firstName.isEmpty ? widget.user.displayName : widget.user.firstName}. '
                        'Tu cuenta ya está creada.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Step(
                    icon: Icons.how_to_reg_rounded,
                    title: 'El club revisa tu registro',
                    message:
                        'Un administrador define tu inscripción y tu '
                        'mensualidad.',
                  ),
                  const _Step(
                    icon: Icons.notifications_active_outlined,
                    title: 'Te avisamos',
                    message:
                        'Cuando esté listo podrás registrar a tus hijos, '
                        'ver tus cobros y subir comprobantes.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _checking ? null : _refresh,
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('Ya me validaron / Actualizar'),
                  ),
                  if (contact != null && contact.hasContact) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _whatsApp,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: const Color(0xFF128C7E),
                        side: const BorderSide(color: Color(0xFF25D366)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.chat_rounded),
                      label: Text(
                        'Escribir a ${contact.contactName ?? 'Tesorería del club'}',
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _checking ? null : _signOut,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                    ),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => ListCard(
    leading: AppAvatar(seed: title, icon: icon),
    title: title,
    subtitle: message,
    subtitleLines: 3,
  );
}
