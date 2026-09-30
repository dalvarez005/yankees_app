import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_colors.dart';

/// Toast arriba de la pantalla, por encima de todo (hojas inferiores y
/// diálogos incluidos). Uno a la vez: el nuevo reemplaza al anterior.
///
/// Verde con check: algo salió bien. Rojo: error. [info]: indicación en azul.
void showAppMessage(
  BuildContext context,
  String message, {
  bool error = false,
  bool info = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) showToast(overlay, message, error: error, info: info);
}

OverlayEntry? _currentToast;

/// Variante sin `BuildContext` (p. ej. desde el `navigatorKey`).
void showToast(
  OverlayState overlay,
  String message, {
  bool error = false,
  bool info = false,
}) {
  _currentToast?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      error: error,
      info: info && !error,
      onDone: () {
        if (_currentToast == entry) _currentToast = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.error,
    required this.info,
    required this.onDone,
  });

  final String message;
  final bool error;
  final bool info;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  )..forward();
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // Los errores quedan un poco más para poder leerlos.
    _timer = Timer(Duration(milliseconds: widget.error ? 4500 : 3000), _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _anim.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.error
        ? AppColors.error
        : widget.info
        ? AppColors.navy
        : AppColors.success;
    final curved = CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, -1.4),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(
              opacity: _anim,
              child: Dismissible(
                key: const ValueKey('toast'),
                direction: DismissDirection.up,
                onDismissed: (_) {
                  _timer?.cancel();
                  widget.onDone();
                },
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    color: Colors.transparent,
                    child: GestureDetector(
                      onTap: _close,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navy.withValues(alpha: 0.14),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                widget.error
                                    ? Icons.error_outline_rounded
                                    : widget.info
                                    ? Icons.info_outline_rounded
                                    : Icons.check_circle_outline_rounded,
                                color: color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.message,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

/// Confirmación estilo nativo (Cupertino en iOS). Devuelve true si acepta.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final ok = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: AppColors.error)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Pantalla para cuando se llega a una sección sin el permiso necesario
/// (p. ej. le quitaron el permiso mientras tenía la app abierta).
class NoAccessView extends StatelessWidget {
  const NoAccessView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 56, color: AppColors.navy),
              SizedBox(height: 16),
              Text(
                'No tienes permiso para ver esta sección.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Si crees que es un error, pide acceso a un administrador.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
