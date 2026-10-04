import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/feedback.dart';
import 'notification_host.dart';

/// Tarjeta del inicio (solo web) para activar los avisos con un toque, o
/// para explicar en iPhone que hay que agregar la app a la pantalla de inicio.
class WebPushPrompt extends StatefulWidget {
  const WebPushPrompt({super.key});

  @override
  State<WebPushPrompt> createState() => _WebPushPromptState();
}

class _WebPushPromptState extends State<WebPushPrompt> {
  bool _busy = false;
  bool _dismissed = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    final ok = await WebPush.enable();
    if (!mounted) return;
    setState(() => _busy = false);
    showAppMessage(
      context,
      ok
          ? 'Listo: te avisaremos en este teléfono.'
          : 'No se activaron los avisos. Puedes permitirlos en los ajustes '
                'del navegador.',
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([WebPush.offer, WebPush.needsInstall]),
    builder: (context, _) {
      if (_dismissed) return const SizedBox.shrink();
      final offer = WebPush.offer.value;
      final install = WebPush.needsInstall.value;
      if (!offer && !install) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE6ECF5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                offer
                    ? Icons.notifications_active_outlined
                    : Icons.add_to_home_screen_rounded,
                color: AppColors.navy,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  offer
                      ? 'Recibe avisos de pagos y validaciones en este teléfono.'
                      : 'Para recibir avisos, agrega la app a tu pantalla de '
                            'inicio: Compartir → Agregar a inicio.',
                  style: const TextStyle(color: AppColors.navy, fontSize: 13),
                ),
              ),
              if (offer)
                TextButton(
                  onPressed: _busy ? null : _enable,
                  child: Text(_busy ? 'Activando…' : 'Activar'),
                )
              else
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => setState(() => _dismissed = true),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.navy,
                ),
            ],
          ),
        ),
      );
    },
  );
}
