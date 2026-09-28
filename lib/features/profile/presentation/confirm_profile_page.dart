import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_colors.dart';
import '../../../app/routes.dart';
import '../../auth/data/app_user.dart';
import '../../auth/data/auth_repository.dart';
import '../data/profile_review_store.dart';
import 'profile_form.dart';

/// Después del primer ingreso en el dispositivo: el usuario confirma o
/// corrige su nombre antes de entrar (sobre todo si vino de una cuenta de
/// Google con un nombre que no es el real). No se puede saltar.
class ConfirmProfilePage extends StatefulWidget {
  const ConfirmProfilePage({super.key, required this.user});

  final AppUser user;

  @override
  State<ConfirmProfilePage> createState() => _ConfirmProfilePageState();
}

class _ConfirmProfilePageState extends State<ConfirmProfilePage> {
  late AppUser _user = widget.user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Parte de los datos más recientes de la API.
  Future<void> _refresh() async {
    try {
      final fresh = await AuthRepository.instance.fetchProfile();
      if (mounted) setState(() => _user = fresh);
    } on AuthException {
      // Sin conexión se usan los datos que ya se tienen.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _confirm(ProfileInput input) async {
    try {
      final updated = await AuthRepository.instance.updateProfile(input);
      await ProfileReviewStore.instance.markReviewed(updated.id);
      if (!mounted) return null;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(Routes.home, (_) => false, arguments: updated);
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  Future<void> _useAnotherAccount() async {
    await AuthRepository.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Fondo claro: íconos de la barra de estado en oscuro.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.navy),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              size: 48,
                              color: AppColors.navy,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Confirma tus datos',
                              style: text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Así te verá el club en pagos e inscripciones. '
                              'Escribe tu nombre real, tal como aparece en tu '
                              'DPI, aunque tu cuenta tenga otro.',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 28),
                            ProfileForm(
                              user: _user,
                              submitLabel: 'Confirmar y continuar',
                              onSubmit: _confirm,
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _useAnotherAccount,
                              child: const Text('Usar otra cuenta'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
