import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/app/app_theme.dart';
import 'package:yankees/features/payments/data/payment_models.dart';
import 'package:yankees/features/payments/data/payments_repository.dart';
import 'package:yankees/features/payments/data/voucher_processor.dart';
import 'package:yankees/features/payments/presentation/charge_detail_page.dart';

/// Tamaño del resultado según lado y calidad (para probar la estrategia).
class _FakeEncoder implements WebpEncoder {
  _FakeEncoder(this.sizeFor);
  final int Function(int side, int quality) sizeFor;
  final calls = <(int, int)>[];

  @override
  Future<List<int>> encode(
    String path, {
    required int maxSide,
    required int quality,
    int? width,
    int? height,
  }) async {
    calls.add((maxSide, quality));
    return List.filled(sizeFor(maxSide, quality), 0);
  }
}

/// Procesador sin plugins: devuelve lo indicado y registra las llamadas.
class _FakeProcessor implements VoucherProcessor {
  _FakeProcessor({this.ocrText, this.signals = const []});
  final String? ocrText;
  final List<String> signals;
  final calls = <String>[];

  @override
  Future<VoucherAnalysis> analyze(String path) async {
    calls.add('analyze');
    return VoucherAnalysis(ocrText: ocrText, editSignals: signals);
  }

  @override
  Future<List<int>> compress(String path, VoucherAnalysis analysis) async {
    calls.add('compress');
    return const [1, 2, 3];
  }
}

/// Registra lo que se sube.
class _SpyPayments extends MockPaymentsRepository {
  _SpyPayments() : super(latency: Duration.zero);
  VoucherForm? form;
  VoucherUpload? upload;

  @override
  Future<Charge> uploadVoucher(
    String chargeId,
    VoucherForm form,
    VoucherUpload file,
  ) {
    this.form = form;
    upload = file;
    return super.uploadVoucher(chargeId, form, file);
  }
}

/// Pantalla alta: las listas perezosas construyen todo el contenido.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('señales de edición (EXIF del original)', () {
    test('software de edición conocido', () {
      final s = detectEditSignals({'Image Software': 'Adobe Photoshop 25.1'});
      expect(s.single, contains('Adobe Photoshop 25.1'));
      expect(detectEditSignals({'Image Software': 'Android 14 UP1A'}), isEmpty);
    });

    test('fecha de modificación distinta de la original', () {
      expect(
        detectEditSignals({
          'Image DateTime': '2026:10:05 09:00:00',
          'EXIF DateTimeOriginal': '2026:10:03 12:00:00',
        }).single,
        contains('distinta de la original'),
      );
      // Iguales (o dentro del minuto) no es señal.
      expect(
        detectEditSignals({
          'Image DateTime': '2026:10:03 12:00:30',
          'EXIF DateTimeOriginal': '2026:10:03 12:00:00',
        }),
        isEmpty,
      );
    });

    test('dimensiones atípicas o distintas del EXIF', () {
      final s = detectEditSignals(
        {'EXIF ExifImageWidth': '4032', 'EXIF ExifImageLength': '3024'},
        width: 1080,
        height: 2400,
      );
      expect(s.single, contains('4032x3024'));
      // Rotada 90° sí coincide.
      expect(
        detectEditSignals(
          {'EXIF ExifImageWidth': '4032', 'EXIF ExifImageLength': '3024'},
          width: 3024,
          height: 4032,
        ),
        isEmpty,
      );
      expect(
        detectEditSignals(const {}, width: 200, height: 1200).single,
        contains('atípicas'),
      );
    });

    test('sin EXIF (captura de pantalla) no hay señales', () {
      expect(detectEditSignals(const {}, width: 1080, height: 2400), isEmpty);
    });

    test('los ; del valor no rompen la lista', () {
      final s = detectEditSignals({'Image Software': 'GIMP; 2.10'});
      expect(s.single, isNot(contains(';')));
    });
  });

  group('compresión', () {
    test('primer intento: WebP lado 1280 calidad 55', () async {
      final enc = _FakeEncoder((_, _) => 120 * 1024);
      final bytes = await compressForUpload(enc, '/x.jpg');
      expect(enc.calls, [(1280, 55)]);
      expect(bytes.length, 120 * 1024);
    });

    test('si pasa de 250 KB baja la calidad y luego el lado', () async {
      // Solo entra en la meta con lado 1024.
      final enc = _FakeEncoder(
        (side, q) => side == 1024 ? 200 * 1024 : 400 * 1024,
      );
      final bytes = await compressForUpload(enc, '/x.jpg');
      expect(enc.calls.first, (1280, 55));
      expect(enc.calls.map((c) => c.$2).where((q) => q < 55), isNotEmpty);
      expect(enc.calls.map((c) => c.$2).reduce((a, b) => a < b ? a : b), 35);
      expect(enc.calls.last, (1024, 35));
      expect(bytes.length, 200 * 1024);
    });

    test('si ninguno llega a la meta usa el más liviano', () async {
      final enc = _FakeEncoder((side, q) => (300 + q) * 1024);
      final bytes = await compressForUpload(enc, '/x.jpg');
      expect(bytes.length, 335 * 1024);
    });

    test('nunca sube más de 2 MB', () async {
      final enc = _FakeEncoder((_, _) => 3 * 1024 * 1024);
      expect(
        () => compressForUpload(enc, '/x.jpg'),
        throwsA(isA<VoucherTooLargeException>()),
      );
    });
  });

  group('sugerencias del OCR', () {
    test('referencia junto a una palabra clave y montos', () {
      final s = suggestFromOcr(
        'BANRURAL\nDEPOSITO MONETARIO\nNo. Boleta: 889231455\n'
        'Fecha 03/10/2026\nMonto Q 1,150.00\nCuenta 3001234567',
      );
      expect(s.reference, '889231455');
      expect(s.amounts, [1150.0]);
    });

    test('sin texto útil no sugiere nada', () {
      final s = suggestFromOcr('hola');
      expect(s.reference, isNull);
      expect(s.amounts, isEmpty);
    });
  });

  group('formulario de comprobante', () {
    late _SpyPayments payments;
    late _FakeProcessor processor;
    late Charge charge;

    setUp(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      payments = _SpyPayments();
      PaymentsRepository.instance = payments;
      charge = (await payments.myCharges()).firstWhere(
        (c) => c.status == ChargeStatus.pending,
      );
    });

    Future<void> pump(WidgetTester tester) async {
      _tall(tester);
      VoucherProcessor.instance = processor;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<Charge>(
                      builder: (_) => UploadVoucherPage(charge: charge),
                    ),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Enviar comprobante'));
      await tester.tap(find.text('Enviar comprobante'));
      await tester.pumpAndSettle();
    }

    testWidgets('todos los campos y la foto son obligatorios', (tester) async {
      processor = _FakeProcessor();
      await pump(tester);
      // El monto viene prellenado con el del cobro.
      expect(find.text(charge.amount.toStringAsFixed(0)), findsOneWidget);

      await send(tester);
      expect(
        find.text('La foto del comprobante es obligatoria'),
        findsOneWidget,
      );
      expect(find.text('Escribe el número de boleta'), findsOneWidget);
      expect(find.text('Escribe una descripción'), findsOneWidget);
      expect(find.text('Elige la fecha de pago'), findsOneWidget);
      expect(payments.form, isNull);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('el monto debe ser igual al del cobro', (tester) async {
      processor = _FakeProcessor();
      await pump(tester);
      await tester.enterText(find.byType(TextFormField).first, '1');
      await send(tester);
      expect(
        find.text(
          'Debe ser igual al cobro (Q ${charge.amount.toStringAsFixed(2)})',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('con la foto analiza, sugiere la boleta, comprime y sube', (
      tester,
    ) async {
      processor = _FakeProcessor(
        ocrText: 'Banco Industrial\nReferencia: 55120993\nQ 999.00',
        signals: const ['Software de edición: Snapseed'],
      );
      await pump(tester);
      final state = tester.state(find.byType(UploadVoucherPage));
      (state as dynamic).setPhoto('/no/existe/boleta.jpg');
      await tester.pumpAndSettle();

      // La referencia se sugirió desde el OCR y se avisa del monto distinto.
      expect(find.text('55120993'), findsOneWidget);
      expect(find.textContaining('En la foto vemos Q 999.00'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Ej. Depósito Banrural '
          '${charge.concept.toLowerCase()}',
        ),
        'Depósito BI inscripción',
      );
      await tester.ensureVisible(find.text('Selecciona la fecha'));
      await tester.tap(find.text('Selecciona la fecha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await send(tester);
      expect(processor.calls, ['analyze', 'compress']);
      expect(payments.form!.bankReference, '55120993');
      expect(payments.form!.amount, charge.amount);
      expect(payments.form!.description, 'Depósito BI inscripción');
      expect(payments.upload!.bytes, [1, 2, 3]);
      expect(payments.upload!.editSignals, ['Software de edición: Snapseed']);
      expect(payments.upload!.ocrText, contains('55120993'));
      // Volvió con el cobro en revisión.
      expect(find.byType(UploadVoucherPage), findsNothing);
    });
  });
}
