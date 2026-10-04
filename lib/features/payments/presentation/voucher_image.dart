import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../data/payment_models.dart';
import '../data/payments_repository.dart';

/// Abre una imagen a pantalla completa, entera (sin recortar) y con zoom.
/// [localPath] para un archivo del teléfono; [url] + [headers] para una de
/// la API (protegida con el token).
Future<void> showImageViewer(
  BuildContext context, {
  String title = 'Comprobante',
  String? localPath,
  String? url,
  Map<String, String> headers = const {},
}) {
  Widget broken(BuildContext _, Object? _, StackTrace? _) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_not_supported_outlined, color: Colors.white70),
        SizedBox(height: 8),
        Text(
          'No se pudo cargar la imagen',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );

  // En web la foto elegida es una URL del navegador (blob:), no un archivo.
  final Widget image = localPath != null
      ? (kIsWeb
            ? Image.network(
                localPath,
                fit: BoxFit.contain,
                errorBuilder: broken,
              )
            : Image.file(
                File(localPath),
                fit: BoxFit.contain,
                errorBuilder: broken,
              ))
      : url != null
      ? Image.network(
          url,
          headers: headers,
          fit: BoxFit.contain,
          errorBuilder: broken,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
        )
      : broken(context, null, null);

  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(title),
        ),
        body: SafeArea(
          child: InteractiveViewer(
            maxScale: 6,
            child: SizedBox.expand(child: image),
          ),
        ),
      ),
    ),
  );
}

/// Fila "Ver imagen" de un comprobante ya enviado. No muestra la foto en
/// línea (un comprobante vertical siempre quedaba recortado): la abre
/// completa al tocarla.
class VoucherImage extends StatelessWidget {
  const VoucherImage({super.key, required this.voucher});

  final Voucher voucher;

  Future<void> _open(BuildContext context) async {
    final v = voucher;
    final repo = PaymentsRepository.instance;
    final headers = v.fileUrl == null
        ? const <String, String>{}
        : await repo.fileHeaders();
    if (!context.mounted) return;
    await showImageViewer(
      context,
      localPath: v.localPath,
      url: v.fileUrl == null ? null : repo.fileUrl(v.fileUrl!),
      headers: headers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = voucher.localPath != null || voucher.fileUrl != null;
    return ImageTile(
      title: 'Foto del comprobante',
      subtitle: available
          ? 'Toca para verla completa'
          : 'La imagen no está disponible',
      onView: available ? () => _open(context) : null,
    );
  }
}

/// Tarjeta compacta que representa una imagen sin mostrarla.
class ImageTile extends StatelessWidget {
  const ImageTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onView,
    this.onChange,
    this.viewLabel = 'Ver imagen',
  });

  final String title;
  final String subtitle;
  final VoidCallback? onView;

  /// Si se indica, muestra "Cambiar" (formulario de subida).
  final VoidCallback? onChange;
  final String viewLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onView,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.image_outlined, color: AppColors.navy),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (onChange != null)
                TextButton(
                  onPressed: onChange,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Cambiar'),
                ),
              TextButton.icon(
                onPressed: onView,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text(viewLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
