import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'payments_repository.dart';
import 'voucher_processor.dart';

/// Android e iOS (selección en `voucher_processor.dart`).
VoucherProcessor createVoucherProcessor() => DeviceVoucherProcessor();

/// Implementación real: `exif`, ML Kit y `flutter_image_compress`.
class DeviceVoucherProcessor implements VoucherProcessor {
  DeviceVoucherProcessor({
    ExifSource? exif,
    TextRecognizerSource? ocr,
    WebpEncoder? encoder,
  }) : _exif = exif ?? PackageExifSource(),
       _ocr = ocr ?? MlKitTextRecognizer(),
       _encoder = encoder ?? NativeWebpEncoder();

  final ExifSource _exif;
  final TextRecognizerSource _ocr;
  final WebpEncoder _encoder;

  @override
  Future<VoucherAnalysis> analyze(String path) async {
    final bytes = await File(path).readAsBytes();
    final size = await imageSize(bytes);
    Map<String, String> exif;
    try {
      exif = await _exif.read(bytes);
    } catch (_) {
      exif = const {};
    }
    String? text;
    try {
      text = await _ocr.recognize(path);
    } catch (_) {
      text = null; // Sin OCR se sigue igual.
    }
    return VoucherAnalysis(
      ocrText: text,
      editSignals: detectEditSignals(exif, width: size?.$1, height: size?.$2),
      width: size?.$1,
      height: size?.$2,
    );
  }

  @override
  Future<List<int>> compress(String path, VoucherAnalysis analysis) =>
      compressForUpload(
        _encoder,
        path,
        width: analysis.width,
        height: analysis.height,
      );
}

/// ML Kit solo existe en Android e iOS.
class MlKitTextRecognizer implements TextRecognizerSource {
  @override
  Future<String?> recognize(String path) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } finally {
      await recognizer.close();
    }
  }
}

class NativeWebpEncoder implements WebpEncoder {
  @override
  Future<List<int>> encode(
    String path, {
    required int maxSide,
    required int quality,
    int? width,
    int? height,
  }) async {
    // El plugin escala hasta que el lado MENOR llegue al mínimo pedido;
    // se calcula ese mínimo para que el MAYOR quede en [maxSide] (y sin
    // agrandar fotos pequeñas).
    var minSide = maxSide;
    if (width != null && height != null && width > 0 && height > 0) {
      final long = width > height ? width : height;
      final short = width > height ? height : width;
      final scale = long > maxSide ? maxSide / long : 1.0;
      minSide = (short * scale).round().clamp(1, maxSide);
    }
    final bytes = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: minSide,
      minHeight: minSide,
      quality: quality,
      format: CompressFormat.webp,
      keepExif: false,
    );
    if (bytes == null || bytes.isEmpty) {
      throw const PaymentsException(
        'No se pudo procesar la foto. Intenta con otra.',
      );
    }
    return bytes;
  }
}
