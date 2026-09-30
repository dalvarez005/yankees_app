import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../data/payment_models.dart';
import '../data/payments_repository.dart';

/// Imagen del comprobante: archivo local (modo simulado) o descargada de la
/// API con el token de la sesión. "Ver completo" la abre con zoom.
class VoucherImage extends StatefulWidget {
  const VoucherImage({super.key, required this.voucher, this.height = 220});

  final Voucher voucher;
  final double height;

  @override
  State<VoucherImage> createState() => _VoucherImageState();
}

class _VoucherImageState extends State<VoucherImage> {
  late final Future<Map<String, String>> _headers = PaymentsRepository.instance
      .fileHeaders();

  Widget _image(BoxFit fit, Map<String, String> headers) {
    final v = widget.voucher;
    if (v.localPath != null) {
      return Image.file(File(v.localPath!), fit: fit, errorBuilder: _broken);
    }
    if (v.fileUrl != null) {
      return Image.network(
        PaymentsRepository.instance.fileUrl(v.fileUrl!),
        headers: headers,
        fit: fit,
        errorBuilder: _broken,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Center(
                child: CircularProgressIndicator(color: AppColors.navy),
              ),
      );
    }
    return _broken(context, null, null);
  }

  Widget _broken(BuildContext context, Object? error, StackTrace? stack) =>
      const ColoredBox(
        color: AppColors.background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                color: AppColors.textMuted,
              ),
              SizedBox(height: 6),
              Text(
                'No se pudo cargar el comprobante',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );

  void _openFull(Map<String, String> headers) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Comprobante'),
          ),
          body: InteractiveViewer(
            maxScale: 5,
            child: Center(child: _image(BoxFit.contain, headers)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _headers,
      builder: (context, snap) {
        final headers = snap.data ?? const <String, String>{};
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _image(BoxFit.cover, headers),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _openFull(headers),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.zoom_out_map_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Ver completo',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
