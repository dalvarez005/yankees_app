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

    test('transferencia BI en español: código de autorización', () {
      final s = suggestFromOcr(
        'Tu transferencia fue realizada\ncon éxito\n29/09/26 10:43:44 PM\n'
        'Código de autorización:\n29245441\nCuenta origen:\n'
        'CHUPINA MENDEZ DIEGO ANDRE\nCUENTA MONETARIA BI\nGTQ-5550047228\n'
        'Cuenta destino:\nsebastian\nCUENTA DE AHORRO BI\nGTQ-1114517\n'
        'Monto:\nGTQ 100.00\nComentario:\nGracias por el prstamo',
        now: DateTime(2026, 9, 30),
      );
      expect(s.reference, '29245441');
      expect(s.amounts, [100.0]);
      expect(s.date, DateTime(2026, 9, 29));
    });

    test('transferencia BI en inglés: authorization code', () {
      final s = suggestFromOcr(
        'Your transfer was made\nsuccessfully.\n10/09/26 06:44:56 PM\n'
        'Authorization code:\n10275027\nAccount of origin:\n'
        'ISTACUY CHUPINA\nSEBASTIAN ALEJANDRO\nSAVINGS ACCOUNT BI\n'
        'GTQ-1114517\nDestination account:\nJORON\nCHECKING ACCOUNT BI\n'
        'GTQ-1030134827\nAmount:\nGTQ 100.00',
        now: DateTime(2026, 9, 30),
      );
      expect(s.reference, '10275027');
      expect(s.amounts, [100.0]);
      expect(s.date, DateTime(2026, 9, 10));
    });

    test('etiqueta y valor en la misma línea, con palabras de relleno', () {
      expect(
        suggestFromOcr('Reference number: TRX-99812\nAmount Q 50.00').reference,
        'TRX-99812',
      );
      expect(
        suggestFromOcr('No. de autorización 7781234').reference,
        '7781234',
      );
    });

    test('sin palabra clave: el número largo que no es cuenta ni fecha', () {
      final s = suggestFromOcr(
        'BANCO X\n03/10/2026 14:22\n445566778899\n'
        'Cuenta destino\n3001234567\nGTQ 250.00',
      );
      expect(s.reference, '445566778899');
    });

    test('no confunde cuentas, montos ni fechas con la referencia', () {
      final s = suggestFromOcr(
        'Cuenta origen:\nGTQ-5550047228\nMonto:\nGTQ 1,500.00\n'
        '29/09/2026',
      );
      expect(s.reference, isNull);
    });

    group('fecha del comprobante', () {
      final now = DateTime(2026, 9, 30);
      DateTime? date(String text) => suggestFromOcr(text, now: now).date;

      test('numérica con /, - y . y año de 2 o 4 dígitos', () {
        expect(date('29/09/26 10:43:44 PM'), DateTime(2026, 9, 29));
        expect(date('Fecha: 29-09-2026'), DateTime(2026, 9, 29));
        expect(date('29.09.2026'), DateTime(2026, 9, 29));
        expect(date('5/9/2026'), DateTime(2026, 9, 5));
        expect(date('2026-09-29 22:43'), DateTime(2026, 9, 29));
      });

      test('con el mes en letras, en español', () {
        expect(date('29 de septiembre de 2026'), DateTime(2026, 9, 29));
        expect(date('Guatemala, 3 de Agosto del 2026'), DateTime(2026, 8, 3));
        expect(date('29 SEP 2026'), DateTime(2026, 9, 29));
        expect(date('29/Sep/26'), DateTime(2026, 9, 29));
        expect(date('05-dic-2025'), DateTime(2025, 12, 5));
        expect(date('29 sept. 2026'), DateTime(2026, 9, 29));
      });

      test('con el mes en letras, en inglés', () {
        expect(date('September 29, 2026'), DateTime(2026, 9, 29));
        expect(date('Sep 29 2026 10:43 PM'), DateTime(2026, 9, 29));
        expect(date('Aug 3rd, 2026'), DateTime(2026, 8, 3));
        expect(date('29 August 2026'), DateTime(2026, 8, 29));
      });

      test('si el primer número no puede ser el día, es mes/día', () {
        expect(date('09/29/2026'), DateTime(2026, 9, 29));
      });

      test('prefiere la que acompaña a "Fecha" o "Date"', () {
        expect(
          date('Válido hasta 01/01/2026\nFecha de operación:\n29/09/2026'),
          DateTime(2026, 9, 29),
        );
        expect(
          date('Printed 01/09/2026\nTransaction date 15/09/2026'),
          DateTime(2026, 9, 15),
        );
      });

      test('descarta fechas imposibles, futuras o muy viejas', () {
        expect(date('31/02/2026'), isNull);
        expect(date('15/10/2026'), isNull); // futura
        expect(date('29/09/2020'), isNull); // de hace años
        expect(date('Cuenta 30-01-234567'), isNull);
      });

      test('boleta impresa del banco (foto)', () {
        final s = suggestFromOcr(
          'BANCO INDUSTRIAL, S.A.\nAGENCIA CENTRAL\nDEPOSITO MONETARIO\n'
          'FECHA 29/SEP/2026 HORA 14:22:10\nNo. DOCUMENTO 0045671238\n'
          'CUENTA 300-123456-7\nNOMBRE CLUB YANKEES\n'
          'EFECTIVO Q. 250.00\nTOTAL Q 250.00\nCAJERO 0871',
          now: now,
        );
        expect(s.date, DateTime(2026, 9, 29));
        expect(s.reference, '0045671238');
        expect(s.amounts, contains(250.0));
        expect(s.readable, isTrue);
      });

      test('una fecha con guiones no se toma como referencia', () {
        final s = suggestFromOcr('29-SEP-2026\n29-09-2026', now: now);
        expect(s.reference, isNull);
        expect(s.date, DateTime(2026, 9, 29));
      });
    });

    test('ilegible: dice qué falta', () {
      final nothing = suggestFromOcr('borroso');
      expect(nothing.readable, isFalse);
      expect(nothing.missing, hasLength(2));
      final noDate = suggestFromOcr('Boleta: 889231455');
      expect(noDate.readable, isFalse);
      expect(noDate.missing, ['la fecha']);
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

    /// null = deshabilitado.
    VoidCallback? sendAction(WidgetTester tester) => tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Enviar comprobante'),
        )
        .onPressed;

    /// Fecha reciente con el formato de los bancos (día/mes/año).
    final paid = DateTime.now().subtract(const Duration(days: 2));
    final paidText =
        '${paid.day.toString().padLeft(2, '0')}/'
        '${paid.month.toString().padLeft(2, '0')}/${paid.year}';

    Future<void> setPhoto(WidgetTester tester) async {
      final state = tester.state(find.byType(UploadVoucherPage));
      (state as dynamic).setPhoto('/no/existe/boleta.jpg');
      await tester.pumpAndSettle();
    }

    Future<void> describe(WidgetTester tester, String text) async {
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Ej. Depósito Banrural ${charge.concept.toLowerCase()}',
        ),
        text,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Enviar está deshabilitado hasta completar todo', (
      tester,
    ) async {
      processor = _FakeProcessor(
        ocrText: 'Banco Industrial\n$paidText\nReferencia: 55120993\nQ 250.00',
      );
      await pump(tester);
      // El monto viene prellenado con el del cobro, pero falta lo demás.
      expect(find.text(charge.amount.toStringAsFixed(0)), findsOneWidget);
      expect(sendAction(tester), isNull);

      // Con la foto leída sigue faltando la descripción.
      await setPhoto(tester);
      expect(sendAction(tester), isNull);

      await describe(tester, 'Dep');
      expect(find.text('Mínimo 5 caracteres'), findsOneWidget);
      expect(sendAction(tester), isNull);

      await describe(tester, 'Depósito BI inscripción');
      expect(sendAction(tester), isNotNull);
      expect(payments.form, isNull);
    });

    testWidgets('el monto debe ser igual al del cobro', (tester) async {
      processor = _FakeProcessor(ocrText: 'Fecha $paidText\nBoleta 55120993');
      await pump(tester);
      await setPhoto(tester);
      await describe(tester, 'Depósito BI inscripción');
      expect(sendAction(tester), isNotNull);

      await tester.enterText(find.byType(TextFormField).first, '1');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Debe ser igual al cobro (Q ${charge.amount.toStringAsFixed(2)})',
        ),
        findsOneWidget,
      );
      expect(sendAction(tester), isNull);
    });

    testWidgets('con la foto lee boleta y fecha, comprime y sube', (
      tester,
    ) async {
      processor = _FakeProcessor(
        ocrText:
            'Banco Industrial\nDate: $paidText\nAuthorization code:\n'
            '55120993\nQ 999.00',
        signals: const ['Software de edición: Snapseed'],
      );
      await pump(tester);
      await setPhoto(tester);

      // Boleta y fecha salen de la foto; se avisa del monto distinto.
      expect(find.text('55120993'), findsOneWidget);
      expect(find.text('Selecciona la fecha'), findsNothing);
      expect(find.textContaining('La leímos de la foto'), findsOneWidget);
      expect(find.textContaining('En la foto vemos Q 999.00'), findsOneWidget);

      await describe(tester, 'Depósito BI inscripción');
      await send(tester);
      expect(processor.calls, ['analyze', 'compress']);
      expect(payments.form!.bankReference, '55120993');
      expect(payments.form!.amount, charge.amount);
      expect(payments.form!.description, 'Depósito BI inscripción');
      expect(
        payments.form!.paymentDate,
        DateTime(paid.year, paid.month, paid.day),
      );
      expect(payments.upload!.bytes, [1, 2, 3]);
      expect(payments.upload!.editSignals, ['Software de edición: Snapseed']);
      expect(payments.upload!.ocrText, contains('55120993'));
      // Volvió con el cobro en revisión.
      expect(find.byType(UploadVoucherPage), findsNothing);
    });

    testWidgets('foto ilegible: pide repetirla y bloquea el envío', (
      tester,
    ) async {
      processor = _FakeProcessor(ocrText: 'bor r oso');
      await pump(tester);
      await setPhoto(tester);

      expect(find.text('No pudimos leer el comprobante'), findsOneWidget);
      expect(find.textContaining('la fecha ni el número'), findsOneWidget);
      expect(find.text('Repetir la foto'), findsOneWidget);
      // Al primer intento todavía no se ofrece llenar a mano.
      expect(find.textContaining('llenar los datos a mano'), findsNothing);
      await describe(tester, 'Depósito BI inscripción');
      expect(sendAction(tester), isNull);

      // Segundo intento fallido: se puede seguir a mano.
      await setPhoto(tester);
      final manual = find.textContaining('llenar los datos a mano');
      await tester.ensureVisible(manual);
      await tester.tap(manual);
      await tester.pumpAndSettle();
      expect(find.text('No pudimos leer el comprobante'), findsNothing);
      // Faltan la boleta y la fecha, que ahora escribe el padre.
      expect(sendAction(tester), isNull);
    });

    testWidgets('una foto legible después de una ilegible quita el aviso', (
      tester,
    ) async {
      processor = _FakeProcessor(ocrText: 'borroso');
      await pump(tester);
      await setPhoto(tester);
      expect(find.text('No pudimos leer el comprobante'), findsOneWidget);

      VoucherProcessor.instance = _FakeProcessor(
        ocrText: 'Fecha $paidText\nNo. Boleta 889231455',
      );
      await setPhoto(tester);
      expect(find.text('No pudimos leer el comprobante'), findsNothing);
      expect(find.text('889231455'), findsOneWidget);
    });

    testWidgets('sin OCR disponible no se exige legibilidad', (tester) async {
      processor = _FakeProcessor(); // ocrText null
      await pump(tester);
      await setPhoto(tester);
      expect(find.text('No pudimos leer el comprobante'), findsNothing);
    });
  });
}
