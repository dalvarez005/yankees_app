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

/// Lo que se pudo leer del comprobante.
class OcrSuggestions {
  const OcrSuggestions({this.reference, this.amounts = const [], this.date});

  /// Número de boleta, autorización o transferencia.
  final String? reference;

  /// Montos en quetzales que aparecen en la foto.
  final List<double> amounts;

  /// Fecha de la operación.
  final DateTime? date;

  /// Un comprobante legible deja ver al menos su fecha y su número.
  bool get readable => reference != null && date != null;

  /// Lo que no se distinguió, para pedir otra foto ("la fecha", …).
  List<String> get missing => [
    if (date == null) 'la fecha',
    if (reference == null) 'el número de boleta o autorización',
  ];
}

/// Palabras que anteceden al número de la operación, en español e inglés
/// (las apps de los bancos se usan en ambos idiomas).
final _referenceKeyword = RegExp(
  r'boleta|referencia|\bref\b|autorizaci[oó]n|authori[sz]ation|'
  r'transacci[oó]n|transaction|\bdocumento\b|\bdocument\b|comprobante|'
  r'operaci[oó]n|confirmaci[oó]n|confirmation|\breference\b|\breceipt\b|'
  r'\bvoucher\b|gesti[oó]n|\bfolio\b|\bticket\b|\btracking\b',
  caseSensitive: false,
);

/// Líneas que hablan de cuentas: sus números no son la referencia.
final _accountLine = RegExp(
  r'cuenta|account|\bGTQ\s*-|\bUSD\s*-|monetaria|ahorro|savings|checking|'
  r'\bNIT\b|tel[eé]fono|phone|\bDPI\b|\bCUI\b',
  caseSensitive: false,
);

final _amountPattern = RegExp(
  r'(?:Q|GTQ)\s*\.?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2})',
  caseSensitive: false,
);

/// Candidatos a referencia en un texto: alfanuméricos con 4+ dígitos que no
/// son fecha, hora, monto ni número de cuenta.
Iterable<String> _referenceTokens(String text) sync* {
  for (final m in RegExp(
    r'[A-Z0-9][A-Z0-9-]{3,59}',
    caseSensitive: false,
  ).allMatches(text)) {
    final token = m.group(0)!;
    if (RegExp(r'\d').allMatches(token).length < 4) continue;
    // 29-09-2026 o 29-SEP-2026 son fechas, no referencias.
    if (_numericDate.hasMatch(token) ||
        _isoDate.hasMatch(token) ||
        _dayMonthName.hasMatch(token)) {
      continue;
    }
    final before = text.substring(0, m.start);
    final after = text.substring(m.end);
    // 29/09/26, 10:43:44, 100.00 o 1,150.00 no son referencias.
    if (RegExp(r'\d[/:.,]$').hasMatch(before)) continue;
    if (RegExp(r'^[/:]\d').hasMatch(after)) continue;
    if (RegExp(r'^[.,]\d').hasMatch(after)) continue;
    // "GTQ-5550047228", "Q 100".
    if (RegExp(
      r'(?:GTQ|USD|Q)\s*-?\s*$',
      caseSensitive: false,
    ).hasMatch(before)) {
      continue;
    }
    if (RegExp(r'^(?:GTQ|USD)-', caseSensitive: false).hasMatch(token)) {
      continue;
    }
    yield token.toUpperCase();
  }
}

/// [now] permite fijar la fecha de hoy en las pruebas.
OcrSuggestions suggestFromOcr(String text, {DateTime? now}) {
  final lines = [
    for (final l in text.split(RegExp(r'[\r\n]+')))
      if (l.trim().isNotEmpty) l.trim(),
  ];

  // 1) Junto a una palabra clave: en lo que sigue de esa línea o en las dos
  //    siguientes (el OCR suele separar la etiqueta del valor).
  String? reference;
  outer:
  for (var i = 0; i < lines.length; i++) {
    final keyword = _referenceKeyword.firstMatch(lines[i]);
    if (keyword == null) continue;
    final sameLine = _referenceTokens(lines[i].substring(keyword.end));
    if (sameLine.isNotEmpty) {
      reference = sameLine.first;
      break;
    }
    for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
      if (_accountLine.hasMatch(lines[j])) break;
      final next = _referenceTokens(lines[j]);
      if (next.isNotEmpty) {
        reference = next.first;
        break outer;
      }
    }
  }

  // 2) Sin palabra clave legible: el primer número largo (6+ dígitos) que
  //    esté solo en su línea y no sea de una cuenta.
  if (reference == null) {
    for (var i = 0; i < lines.length; i++) {
      if (_accountLine.hasMatch(lines[i])) continue;
      if (i > 0 &&
          _accountLine.hasMatch(lines[i - 1]) &&
          !RegExp(r'\d').hasMatch(lines[i - 1])) {
        continue;
      }
      final tokens = _referenceTokens(lines[i]).toList();
      if (tokens.length == 1 &&
          tokens.single.length == lines[i].length &&
          RegExp(r'\d').allMatches(tokens.single).length >= 6) {
        reference = tokens.single;
        break;
      }
    }
  }

  final amounts = [
    for (final m in _amountPattern.allMatches(text))
      ?double.tryParse(m.group(1)!.replaceAll(',', '')),
  ];
  return OcrSuggestions(
    reference: reference,
    amounts: amounts,
    date: _dateFrom(text, now: now),
  );
}

/// Meses en español e inglés, completos y abreviados.
const _months = {
  'ene': 1,
  'enero': 1,
  'jan': 1,
  'january': 1,
  'feb': 2,
  'febrero': 2,
  'february': 2,
  'mar': 3,
  'marzo': 3,
  'march': 3,
  'abr': 4,
  'abril': 4,
  'apr': 4,
  'april': 4,
  'may': 5,
  'mayo': 5,
  'jun': 6,
  'junio': 6,
  'june': 6,
  'jul': 7,
  'julio': 7,
  'july': 7,
  'ago': 8,
  'agosto': 8,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'set': 9,
  'septiembre': 9,
  'setiembre': 9,
  'september': 9,
  'oct': 10,
  'octubre': 10,
  'october': 10,
  'nov': 11,
  'noviembre': 11,
  'november': 11,
  'dic': 12,
  'diciembre': 12,
  'dec': 12,
  'december': 12,
};

/// 29/09/26, 29-09-2026, 29.09.2026 (día primero, como en Guatemala).
final _numericDate = RegExp(
  r'(?<!\d)(\d{1,2})\s?[/\-.]\s?(\d{1,2})\s?[/\-.]\s?(\d{4}|\d{2})(?!\d)',
);

/// 2026-09-29.
final _isoDate = RegExp(
  r'(?<!\d)(\d{4})\s?[/\-.]\s?(\d{1,2})\s?[/\-.]\s?(\d{1,2})(?!\d)',
);

/// 29 de septiembre de 2026, 29 SEP 2026, 29/Sep/26, 29-sept.-2026.
final _dayMonthName = RegExp(
  r'(?<!\d)(\d{1,2})\s*(?:de\s+|[/\-.\s]\s*)([A-Za-zÁÉÍÓÚáéíóú]{3,10})\.?'
  r'\s*(?:de\s+|del\s+|[/\-.,\s]\s*)(\d{4}|\d{2})(?!\d)',
  caseSensitive: false,
);

/// September 29, 2026 / Sep 29 2026.
final _monthNameDay = RegExp(
  r'\b([A-Za-z]{3,10})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})(?!\d)',
  caseSensitive: false,
);

final _dateLabel = RegExp(
  r'\bfecha\b|\bdate\b|\bemitid|\bissued',
  caseSensitive: false,
);

/// Fecha real, no futura y de los últimos 400 días; si no, null.
DateTime? _validDate(int year, int month, int day, DateTime now) {
  if (year < 100) year += 2000;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.month != month || date.day != day) return null;
  // Un día de margen por la zona horaria del teléfono.
  if (date.isAfter(now.add(const Duration(days: 1)))) return null;
  if (now.difference(date).inDays > 400) return null;
  return date;
}

/// Fecha de la operación en el texto del comprobante. Si hay varias se
/// prefiere la que acompaña a "Fecha"/"Date"; si no, la primera.
DateTime? _dateFrom(String text, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final found = <({int start, DateTime date})>[];

  void add(int start, DateTime? date) {
    if (date != null) found.add((start: start, date: date));
  }

  for (final m in _isoDate.allMatches(text)) {
    add(
      m.start,
      _validDate(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        today,
      ),
    );
  }
  for (final m in _numericDate.allMatches(text)) {
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    // Día/mes; si no puede ser (13/25/2026 no existe), mes/día.
    add(
      m.start,
      _validDate(year, b, a, today) ?? _validDate(year, a, b, today),
    );
  }
  for (final m in _dayMonthName.allMatches(text)) {
    final month = _months[_plain(m.group(2)!)];
    if (month == null) continue;
    add(
      m.start,
      _validDate(int.parse(m.group(3)!), month, int.parse(m.group(1)!), today),
    );
  }
  for (final m in _monthNameDay.allMatches(text)) {
    final month = _months[_plain(m.group(1)!)];
    if (month == null) continue;
    add(
      m.start,
      _validDate(int.parse(m.group(3)!), month, int.parse(m.group(2)!), today),
    );
  }
  if (found.isEmpty) return null;
  found.sort((x, y) => x.start.compareTo(y.start));

  // Junto a su etiqueta: en la misma línea o justo debajo.
  for (final label in _dateLabel.allMatches(text)) {
    final rest = text.substring(label.end);
    final lines = rest.split(RegExp(r'[\r\n]+'));
    final reach = label.end + lines.take(2).join('\n').length;
    for (final f in found) {
      if (f.start >= label.end && f.start <= reach) return f.date;
    }
  }
  return found.first.date;
}

/// "Septiembre" → "septiembre", "DIC" → "dic" (sin tildes).
String _plain(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u');

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
