import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'payments_repository.dart';
import 'voucher_processor.dart';

/// Versión web (selección en `voucher_processor.dart`): el navegador no tiene
/// ML Kit ni compresor nativo, así que la API lee el comprobante y recibe la
/// foto tal cual (el selector ya la achica, ver `pickVoucherPhoto`).
VoucherProcessor createVoucherProcessor() => WebVoucherProcessor();

class WebVoucherProcessor implements VoucherProcessor {
  WebVoucherProcessor({ExifSource? exif, this._repository})
    : _exif = exif ?? PackageExifSource();

  final ExifSource _exif;
  final PaymentsRepository? _repository;

  /// Límite de la API para la foto original.
  static const maxBytes = 8 * 1024 * 1024;

  final _bytes = <String, Uint8List>{};

  Future<Uint8List> _read(String path) async =>
      _bytes[path] ??= await XFile(path).readAsBytes();

  @override
  Future<VoucherAnalysis> analyze(String path) async {
    final bytes = await _read(path);
    final size = await imageSize(bytes);
    Map<String, String> exif;
    try {
      exif = await _exif.read(bytes);
    } catch (_) {
      exif = const {};
    }
    final repository = _repository ?? PaymentsRepository.instance;
    // Si la API no puede leerlo, la pantalla pide repetir la foto.
    final text = await repository.readVoucherText(bytes);
    return VoucherAnalysis(
      ocrText: text ?? '',
      editSignals: detectEditSignals(exif, width: size?.$1, height: size?.$2),
      width: size?.$1,
      height: size?.$2,
    );
  }

  @override
  Future<List<int>> compress(String path, VoucherAnalysis analysis) async {
    final bytes = await _read(path);
    if (bytes.length > maxBytes) throw const VoucherTooLargeException();
    return bytes;
  }
}
