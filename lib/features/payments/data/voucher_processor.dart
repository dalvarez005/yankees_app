import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'payments_repository.dart';

/// Etapas visibles al enviar un comprobante.
enum VoucherStage {
  analyzing('Analizando la foto…'),
  compressing('Comprimiendo…'),
  uploading('Subiendo…');

  const VoucherStage(this.label);
  final String label;
}

/// Lo que se detectó en la foto ORIGINAL (antes de comprimir).
class VoucherAnalysis {
  const VoucherAnalysis({
    this.ocrText,
    this.editSignals = const [],
    this.width,
    this.height,
  });

  /// Texto reconocido en el dispositivo; null si no hay OCR.
  final String? ocrText;

  /// Indicios de edición (no bloquean; se envían al validador).
  final List<String> editSignals;

  /// Tamaño real de la imagen en píxeles (null si no se pudo leer).
  final int? width;
  final int? height;
}

/// Prepara la foto de un comprobante: lee EXIF y texto del original y la
/// comprime para subirla. Se inyecta para probar sin plugins nativos.
abstract class VoucherProcessor {
  static VoucherProcessor instance = DeviceVoucherProcessor();

  Future<VoucherAnalysis> analyze(String path);

  /// WebP liviano sin metadatos (ver [compressForUpload]).
  Future<List<int>> compress(String path, VoucherAnalysis analysis);
}

/// Etiquetas EXIF como texto ("Image Software" → "Snapseed 2.0").
abstract class ExifSource {
  Future<Map<String, String>> read(Uint8List bytes);
}

/// OCR en el dispositivo; null si no está disponible.
abstract class TextRecognizerSource {
  Future<String?> recognize(String path);
}

/// Codifica a WebP sin metadatos con el lado mayor en [maxSide] como
/// máximo. [width]/[height] son las del original (null si se desconocen).
abstract class WebpEncoder {
  Future<List<int>> encode(
    String path, {
    required int maxSide,
    required int quality,
    int? width,
    int? height,
  });
}

class VoucherTooLargeException extends PaymentsException {
  const VoucherTooLargeException()
    : super(
        'La foto es muy pesada incluso comprimida. Toma una foto más '
        'cercana del comprobante.',
      );
}

/// Meta de peso de la app y máximo que acepta la API.
const voucherTargetBytes = 250 * 1024;
const voucherMaxBytes = 2 * 1024 * 1024;

/// Intentos en orden: lado mayor 1280 con calidad 55 y, si pesa más de
/// 250 KB, bajando la calidad hasta 35 y luego el lado a 1024.
const voucherCompressionSteps = [
  (1280, 55),
  (1280, 50),
  (1280, 45),
  (1280, 40),
  (1280, 35),
  (1024, 35),
];

/// Estrategia de compresión: el primer intento que quede en 250 KB o menos;
/// si ninguno, el más liviano, siempre que no pase de 2 MB.
Future<List<int>> compressForUpload(
  WebpEncoder encoder,
  String path, {
  int? width,
  int? height,
}) async {
  List<int>? best;
  for (final (side, quality) in voucherCompressionSteps) {
    final bytes = await encoder.encode(
      path,
      maxSide: side,
      quality: quality,
      width: width,
      height: height,
    );
    if (bytes.length <= voucherTargetBytes) return bytes;
    if (best == null || bytes.length < best.length) best = bytes;
  }
  if (best == null || best.length > voucherMaxBytes) {
    throw const VoucherTooLargeException();
  }
  return best;
}

final _editors = RegExp(
  r'photoshop|gimp|snapseed|lightroom|picsart|canva|pixlr|fotor|editor|'
  r'affinity|pixelmator|facetune|vsco|polarr|meitu|photodirector|airbrush|'
  r'inshot|paint',
  caseSensitive: false,
);

/// Señales de edición a partir del EXIF del original (heurística del
/// contrato): software de edición, fecha de modificación distinta de la
/// original y dimensiones atípicas o que no coinciden con el EXIF.
List<String> detectEditSignals(
  Map<String, String> exif, {
  int? width,
  int? height,
}) {
  final signals = <String>[];
  String? tag(String name) {
    final v = exif[name]?.trim();
    return (v == null || v.isEmpty) ? null : v.replaceAll(';', ',');
  }

  for (final key in ['Image Software', 'Image ProcessingSoftware']) {
    final software = tag(key);
    if (software != null && _editors.hasMatch(software)) {
      signals.add('Software de edición: $software');
      break;
    }
  }

  final modified = tag('Image DateTime');
  final original = tag('EXIF DateTimeOriginal');
  if (modified != null && original != null) {
    final a = _exifDate(modified);
    final b = _exifDate(original);
    // Un minuto de tolerancia: algunos teléfonos redondean distinto.
    final differs = a != null && b != null
        ? a.difference(b).inSeconds.abs() > 60
        : modified != original;
    if (differs) {
      signals.add(
        'Fecha de modificación ($modified) distinta de la '
        'original ($original)',
      );
    }
  }

  final ew = int.tryParse(tag('EXIF ExifImageWidth') ?? '');
  final eh = int.tryParse(tag('EXIF ExifImageLength') ?? '');
  if (width != null && height != null) {
    if (ew != null &&
        eh != null &&
        !((ew == width && eh == height) || (ew == height && eh == width))) {
      signals.add(
        'Dimensiones EXIF ${ew}x$eh distintas de la imagen '
        '${width}x$height',
      );
    }
    final long = width > height ? width : height;
    final short = width > height ? height : width;
    if (short < 300 || long / short > 5) {
      signals.add('Dimensiones atípicas ${width}x$height');
    }
  }
  return signals;
}

/// "2026:10:03 12:00:00" → fecha.
DateTime? _exifDate(String v) {
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
      .firstMatch(v);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
}

/// Lo que el OCR sugiere para el formulario.
class OcrSuggestions {
  const OcrSuggestions({this.reference, this.amounts = const []});

  /// Número de boleta/transferencia junto a una palabra clave.
  final String? reference;

  /// Montos en quetzales que aparecen en la foto.
  final List<double> amounts;
}

final _referencePattern = RegExp(
  r'(?:boleta|referencia|ref|autorizaci[oó]n|transacci[oó]n|documento|'
  r'comprobante|operaci[oó]n)\s*(?:no\.?|n[uú]m(?:ero)?\.?|#)?\s*[:#.]?\s*'
  r'([A-Z0-9][A-Z0-9-]{3,59})',
  caseSensitive: false,
);

final _amountPattern = RegExp(
  r'(?:Q|GTQ)\s*\.?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2})',
  caseSensitive: false,
);

OcrSuggestions suggestFromOcr(String text) {
  String? reference;
  for (final m in _referencePattern.allMatches(text)) {
    final token = m.group(1)!;
    // Al menos 4 dígitos: descarta palabras sueltas.
    if (RegExp(r'\d').allMatches(token).length >= 4) {
      reference = token.toUpperCase();
      break;
    }
  }
  final amounts = [
    for (final m in _amountPattern.allMatches(text))
      ?double.tryParse(m.group(1)!.replaceAll(',', '')),
  ];
  return OcrSuggestions(reference: reference, amounts: amounts);
}

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
    final size = await _imageSize(bytes);
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

  /// Ancho y alto sin decodificar la imagen completa.
  static Future<(int, int)?> _imageSize(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (descriptor.width, descriptor.height);
      descriptor.dispose();
      buffer.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }
}

class PackageExifSource implements ExifSource {
  @override
  Future<Map<String, String>> read(Uint8List bytes) async {
    final tags = await readExifFromBytes(bytes);
    return {for (final e in tags.entries) e.key: e.value.printable};
  }
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
