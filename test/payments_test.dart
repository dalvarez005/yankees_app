import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yankees/core/format/formats.dart';
import 'package:yankees/core/network/api_client.dart';
import 'package:yankees/features/family/data/dependent.dart';
import 'package:yankees/features/family/data/dependent_repository.dart';
import 'package:yankees/features/payments/data/payment_models.dart';
import 'package:yankees/features/payments/data/payments_repository.dart';

Charge _charge(
  String id,
  ChargeStatus status,
  double amount, {
  String kid = 'd1',
}) => Charge(
  id: id,
  dependentId: kid,
  dependentName: 'Sofía',
  concept: 'Mensualidad',
  amount: amount,
  status: status,
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  group('formatos', () {
    test('quetzales con miles y centavos', () {
      expect(formatMoney(0), 'Q 0.00');
      expect(formatMoney(150), 'Q 150.00');
      expect(formatMoney(1250.5), 'Q 1,250.50');
      expect(formatMoney(1234567.891), 'Q 1,234,567.89');
    });

    test('fecha en español', () {
      expect(formatDate(DateTime(2026, 9, 29)), '29 sep 2026');
    });
  });

  group('Balance', () {
    test('suma lo pendiente, en revisión y rechazado; no lo pagado', () {
      final b = Balance([
        _charge('1', ChargeStatus.pending, 100),
        _charge('2', ChargeStatus.inReview, 50),
        _charge('3', ChargeStatus.rejected, 25),
        _charge('4', ChargeStatus.paid, 1000),
        _charge('5', ChargeStatus.cancelled, 999),
      ]);
      expect(b.totalOwed, 175);
      expect(b.totalInReview, 50);
      expect(b.solvent, isFalse);
      expect(b.paid.single.id, '4');
    });

    test('solvencia por hijo', () {
      final b = Balance([
        _charge('1', ChargeStatus.pending, 100, kid: 'a'),
        _charge('2', ChargeStatus.paid, 100, kid: 'b'),
      ]);
      expect(b.solventFor('a'), isFalse);
      expect(b.solventFor('b'), isTrue);
      expect(b.owedBy('a'), 100);
    });

    test('sin cobros abiertos está solvente', () {
      expect(Balance([_charge('1', ChargeStatus.paid, 10)]).solvent, isTrue);
      expect(const Balance([]).solvent, isTrue);
    });
  });

  group('flujo completo (simulado)', () {
    late MockPaymentsRepository repo;

    setUp(() async {
      final kids = MockDependentRepository(latency: Duration.zero);
      DependentRepository.instance = kids;
      for (final (cui, name) in [
        ('1234567890101', 'Sofía'),
        ('1234567890102', 'Mateo'),
      ]) {
        await kids.add(
          DependentInput(
            cui: cui,
            firstName: name,
            firstLastName: 'Castro',
            categoryId: 2,
          ),
        );
      }
      repo = MockPaymentsRepository(latency: Duration.zero);
    });

    test('subir → rechazar con motivo → subir otro → aprobar', () async {
      final kids = await DependentRepository.instance.list();
      expect(kids, hasLength(2));
      final pending = (await repo.myCharges()).firstWhere(
        (c) => c.status == ChargeStatus.pending,
      );

      final sent = await repo.uploadVoucher(
        pending.id,
        filePath: '/tmp/boleta.jpg',
        reference: ' 889231 ',
      );
      expect(sent.status, ChargeStatus.inReview);
      expect(sent.voucher!.reference, '889231');
      expect((await repo.reviewQueue()).map((c) => c.id), [pending.id]);

      // Rechazar sin motivo no se permite.
      expect(
        () => repo.reviewVoucher(sent.voucher!.id, approve: false),
        throwsA(isA<PaymentsException>()),
      );
      final rejected = await repo.reviewVoucher(
        sent.voucher!.id,
        approve: false,
        comment: 'El monto no coincide.',
      );
      expect(rejected.status, ChargeStatus.rejected);
      expect(rejected.voucher!.reviewComment, 'El monto no coincide.');
      expect(rejected.status.owes, isTrue);

      final again = await repo.uploadVoucher(
        pending.id,
        filePath: '/tmp/boleta2.jpg',
      );
      final paid = await repo.reviewVoucher(again.voucher!.id, approve: true);
      expect(paid.status, ChargeStatus.paid);
      expect(paid.paidAt, isNotNull);
      expect(await repo.reviewQueue(), isEmpty);
    });

    test('no se sube comprobante a un cobro en revisión', () async {
      final c = (await repo.myCharges()).firstWhere(
        (c) => c.status == ChargeStatus.pending,
      );
      await repo.uploadVoucher(c.id, filePath: '/tmp/a.jpg');
      expect(
        () => repo.uploadVoucher(c.id, filePath: '/tmp/b.jpg'),
        throwsA(isA<PaymentsException>()),
      );
    });

    test('asignar por categoría crea un cobro por hijo', () async {
      final kids = await DependentRepository.instance.list();
      final category = kids.first.categoryId;
      final expected = kids.where((d) => d.categoryId == category).length;
      final created = await repo.assignCharge(
        concept: 'Uniforme',
        amount: 175,
        categoryId: category,
      );
      expect(created, expected);
      final charges = await repo.charges(status: ChargeStatus.pending);
      expect(
        charges.where((c) => c.concept == 'Uniforme'),
        hasLength(expected),
      );
    });

    test('anulado no cuenta para el saldo', () async {
      final c = (await repo.myCharges()).firstWhere(
        (c) => c.status == ChargeStatus.pending,
      );
      await repo.cancelCharge(c.id);
      final mine = await repo.myCharges();
      expect(mine.any((x) => x.id == c.id), isFalse);
    });
  });

  group('contrato con la API', () {
    late List<http.BaseRequest> requests;

    ApiPaymentsRepository repo(Object body) {
      requests = [];
      return ApiPaymentsRepository(
        ApiClient(
          baseUrl: 'http://api.test',
          client: MockClient((req) async {
            requests.add(req);
            return http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
    }

    Map<String, dynamic> sent() =>
        jsonDecode((requests.last as http.Request).body)
            as Map<String, dynamic>;

    test('mis cobros se leen de chargeData', () async {
      final r = repo({
        'responseCode': '00',
        'chargeData': [
          {
            'chargeId': 'c1',
            'dependentId': 'd1',
            'dependentName': 'Sofía Castro',
            'concept': 'Inscripción',
            'amount': 250,
            'dueDate': '2026-10-15',
            'status': 'X',
            'createdAt': '2026-09-20T10:00:00Z',
            'voucher': {
              'voucherId': 'v1',
              'status': 'X',
              'uploadedAt': '2026-09-21T09:00:00Z',
              'fileUrl': '/api/Payment/GetVoucherFile/v1',
              'reviewComment': 'Ilegible',
            },
          },
        ],
      });
      final list = await r.myCharges();
      expect(requests.single.url.path, '/api/Payment/GetMyCharges');
      final c = list.single;
      expect(c.status, ChargeStatus.rejected);
      expect(c.amount, 250);
      expect(c.voucher!.reviewComment, 'Ilegible');
      expect(
        r.fileUrl(c.voucher!.fileUrl!),
        'http://api.test/api/Payment/GetVoucherFile/v1',
      );
    });

    test('asignar por categoría', () async {
      final r = repo({'responseCode': '00', 'createdCount': 12});
      final n = await r.assignCharge(
        concept: ' Mensualidad ',
        amount: 100,
        dueDate: DateTime(2026, 10, 5),
        categoryId: 3,
      );
      expect(n, 12);
      expect(requests.single.url.path, '/api/Payment/ManageCharge');
      expect(sent(), {
        'typeOperation': 'A',
        'chargeData': {
          'concept': 'Mensualidad',
          'amount': 100.0,
          'dueDate': '2026-10-05',
          'categoryId': 3,
        },
      });
    });

    test('rechazar manda decision X y el comentario', () async {
      final r = repo({'responseCode': '00', 'chargeData': {}});
      await r.reviewVoucher('v9', approve: false, comment: ' Ilegible ');
      expect(requests.single.url.path, '/api/Payment/ReviewVoucher');
      expect(sent(), {
        'voucherId': 'v9',
        'decision': 'X',
        'comment': 'Ilegible',
      });
    });

    test('contacto: solo dígitos', () async {
      final r = repo({
        'responseCode': '00',
        'settingsData': {'whatsappNumber': '+502 5555-1234'},
      });
      final c = await r.contact();
      expect(c.whatsappNumber, '50255551234');
    });
  });

  test('Dependent sigue construyéndose igual', () {
    // Guardia: el mock de pagos usa estos campos.
    const d = Dependent(
      id: '1',
      cui: '1234567890101',
      firstName: 'Ana',
      firstLastName: 'Gómez',
      categoryId: 2,
    );
    expect(d.fullName, 'Ana Gómez');
  });
}
