import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yankees/core/format/formats.dart';
import 'package:yankees/core/network/api_client.dart';
import 'package:yankees/features/admin/data/admin_repository.dart';
import 'package:yankees/features/billing/data/billing_models.dart';
import 'package:yankees/features/billing/data/billing_repository.dart';
import 'package:yankees/features/notifications/data/notification_repository.dart';
import 'package:yankees/features/payments/data/payment_models.dart';
import 'package:yankees/features/payments/data/payments_repository.dart';
import 'package:yankees/features/payments/data/settings_repository.dart';

Charge _charge(
  String id,
  ChargeStatus status,
  double amount, {
  DateTime? due,
  bool? overdue,
}) => Charge(
  id: id,
  type: ChargeType.monthly,
  concept: 'Mensualidad',
  amount: amount,
  status: status,
  dueDate: due,
  overdue: overdue,
  createdAt: DateTime(2026, 9, 1),
);

VoucherForm _form(double amount, {String ref = 'A-10020'}) => VoucherForm(
  amount: amount,
  bankReference: ref,
  description: 'Depósito Banrural mensualidad',
  paymentDate: DateTime(2026, 10, 3),
);

const _file = VoucherUpload(bytes: [1, 2, 3]);

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

    test('período en español', () {
      expect(formatPeriod('2026-10'), 'Octubre 2026');
      expect(periodOf(DateTime(2026, 3, 9)), '2026-03');
      expect(isoDay(DateTime(2026, 3, 9)), '2026-03-09');
    });
  });

  group('AccountBalance.fromCharges', () {
    final past = DateTime.now().subtract(const Duration(days: 3));
    final future = DateTime.now().add(const Duration(days: 5));

    test('vencido por pagar o rechazado hace insolvente', () {
      final b = AccountBalance.fromCharges([
        _charge('1', ChargeStatus.pending, 100, due: past),
        _charge('2', ChargeStatus.rejected, 25, due: past),
        _charge('3', ChargeStatus.pending, 50, due: future),
        _charge('4', ChargeStatus.paid, 1000, due: past),
      ]);
      expect(b.solvent, isFalse);
      expect(b.overdueAmount, 125);
      expect(b.totalOwed, 175);
      expect(b.nextDueDate, future);
    });

    test('en revisión no hace insolvente aunque haya vencido', () {
      final b = AccountBalance.fromCharges([
        _charge('1', ChargeStatus.inReview, 150, due: past),
      ]);
      expect(b.solvent, isTrue);
      expect(b.inReviewAmount, 150);
      expect(b.clear, isFalse);
    });

    test('sin cobros abiertos está al día', () {
      expect(AccountBalance.fromCharges(const []).clear, isTrue);
    });

    test('overdue de la API tiene prioridad sobre el cálculo', () {
      expect(
        _charge(
          '1',
          ChargeStatus.pending,
          1,
          due: past,
          overdue: false,
        ).overdue,
        isFalse,
      );
    });
  });

  group('flujo simulado', () {
    late MockPaymentsRepository repo;

    setUp(() => repo = MockPaymentsRepository(latency: Duration.zero));

    Future<Charge> pending() async => (await repo.myCharges()).firstWhere(
      (c) => c.status == ChargeStatus.pending,
    );

    test('subir → rechazar con motivo → subir otro → aprobar', () async {
      final c = await pending();
      final sent = await repo.uploadVoucher(c.id, _form(c.amount), _file);
      expect(sent.status, ChargeStatus.inReview);
      expect(sent.voucher!.bankReference, 'A-10020');
      expect(sent.voucher!.amount, c.amount);
      expect((await repo.reviewQueue()).map((x) => x.id), contains(c.id));

      // Motivo obligatorio (mínimo 10).
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

      // La referencia de un rechazado se puede volver a usar.
      final again = await repo.uploadVoucher(c.id, _form(c.amount), _file);
      final paid = await repo.reviewVoucher(again.voucher!.id, approve: true);
      expect(paid.status, ChargeStatus.paid);
      expect(paid.paidAt, isNotNull);
    });

    test('el monto debe ser igual al del cobro', () async {
      final c = await pending();
      expect(
        () => repo.uploadVoucher(c.id, _form(c.amount + 1), _file),
        throwsA(
          isA<PaymentsException>().having(
            (e) => e.message,
            'message',
            contains('igual al del cobro'),
          ),
        ),
      );
    });

    test('no se reutiliza una referencia vigente', () async {
      final mine = (await repo.myCharges())
          .where((c) => c.status == ChargeStatus.pending)
          .toList();
      await repo.uploadVoucher(mine[0].id, _form(mine[0].amount), _file);
      expect(
        () => repo.uploadVoucher(mine[1].id, _form(mine[1].amount), _file),
        throwsA(isA<PaymentsException>()),
      );
    });

    test('anulado no aparece en mis cobros', () async {
      final c = await pending();
      await repo.cancelCharge(c.id);
      expect((await repo.myCharges()).any((x) => x.id == c.id), isFalse);
    });

    test('recordatorio: máximo uno cada 24 h', () async {
      final users = (await repo.insolventUsers()).users;
      expect(users, isNotEmpty);
      final first = await repo.notifyInsolvents();
      expect(first.notified, users.length);
      expect(first.skipped, 0);
      final second = await repo.notifyInsolvents(userIds: [users.first.userId]);
      expect(second.notified, 0);
      expect(second.skipped, 1);
    });

    test('insolventes por categoría de sus hijos', () async {
      final all = (await repo.insolventUsers()).users;
      final cat3 = (await repo.insolventUsers(categoryId: 3)).users;
      expect(cat3.length, lessThanOrEqualTo(all.length));
      expect(
        cat3.every((u) => u.dependents.any((d) => d.categoryId == 3)),
        isTrue,
      );
    });
  });

  group('contrato con la API', () {
    late List<http.Request> requests;
    Object body = const {};

    ApiClient api(Object response) {
      requests = [];
      body = response;
      return ApiClient(
        baseUrl: 'http://api.test',
        client: MockClient((req) async {
          requests.add(req);
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    }

    Map<String, dynamic> sent() =>
        jsonDecode(requests.last.body) as Map<String, dynamic>;

    final chargeJson = {
      'chargeId': 'c1',
      'userId': 'u1',
      'type': 'M',
      'concept': 'Mensualidad octubre 2026',
      'period': '2026-10',
      'amount': 150.0,
      'dueDate': '2026-10-15',
      'status': 'X',
      'overdue': true,
      'createdAt': '2026-10-01T06:00:00Z',
      'paidAt': null,
      'paidOnTime': null,
      'parentName': 'Luis Istacuy',
      'parentEmail': 'luis@correo.com',
      'voucher': {
        'voucherId': 'v1',
        'status': 'X',
        'uploadedAt': '2026-10-03T15:00:00Z',
        'fileUrl': '/api/Payment/GetVoucherFile/v1',
        'amount': 150.0,
        'bankReference': '889231',
        'description': 'Depósito Banrural',
        'paymentDate': '2026-10-03',
        'suspectedEdit': true,
        'editSignals': 'Software de edición: Snapseed;Dimensiones atípicas',
        'reviewComment': 'Ilegible',
        'reviewedAt': '2026-10-04T10:00:00Z',
        'reviewedBy': 'Tesorería',
      },
    };

    test('GetMyCharges: cobro por usuario con comprobante v2', () async {
      final r = ApiPaymentsRepository(
        api({
          'responseCode': '00',
          'chargeData': [chargeJson],
        }),
      );
      final c = (await r.myCharges()).single;
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/Payment/GetMyCharges');
      expect(c.type, ChargeType.monthly);
      expect(c.period, '2026-10');
      expect(c.status, ChargeStatus.rejected);
      expect(c.overdue, isTrue);
      expect(c.parentName, 'Luis Istacuy');
      final v = c.voucher!;
      expect(v.amount, 150);
      expect(v.bankReference, '889231');
      expect(v.paymentDate, DateTime(2026, 10, 3));
      expect(v.suspectedEdit, isTrue);
      expect(v.editSignalList, [
        'Software de edición: Snapseed',
        'Dimensiones atípicas',
      ]);
      expect(
        r.fileUrl(v.fileUrl!),
        'http://api.test/api/Payment/GetVoucherFile/v1',
      );
    });

    test('GetMyBalance', () async {
      final r = ApiPaymentsRepository(
        api({
          'responseCode': '00',
          'balanceData': {
            'solvent': false,
            'totalOwed': 400.0,
            'overdueAmount': 150.0,
            'inReviewAmount': 0,
            'nextDueDate': '2026-11-15',
          },
        }),
      );
      final b = await r.myBalance();
      expect(requests.single.url.path, '/api/Payment/GetMyBalance');
      expect(b.solvent, isFalse);
      expect(b.totalOwed, 400);
      expect(b.overdueAmount, 150);
      expect(b.nextDueDate, DateTime(2026, 11, 15));
    });

    test('UploadVoucher: multipart con todos los campos', () async {
      final r = ApiPaymentsRepository(
        api({'responseCode': '00', 'chargeData': chargeJson}),
      );
      await r.uploadVoucher(
        'c1',
        VoucherForm(
          amount: 150,
          bankReference: ' 889231 ',
          description: ' Depósito Banrural ',
          paymentDate: DateTime(2026, 10, 3),
        ),
        VoucherUpload(
          bytes: const [82, 73, 70, 70],
          ocrText: 'BANRURAL ${'X' * 5000}',
          editSignals: const ['Software de edición: GIMP', 'Otra'],
        ),
      );
      final req = requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/api/Payment/UploadVoucher');
      expect(req.headers['content-type'], startsWith('multipart/form-data'));
      final raw = utf8.decode(req.bodyBytes);
      // Los valores no ASCII llevan su propio content-type en la parte.
      String? field(String name) =>
          RegExp('name="$name"\\r\\n(?:[^\\r]+\\r\\n)*\\r\\n([^\\r]*)\\r\\n')
              .firstMatch(raw)
              ?.group(1);
      expect(field('chargeId'), 'c1');
      expect(field('amount'), '150.00');
      expect(field('bankReference'), '889231');
      expect(field('description'), 'Depósito Banrural');
      expect(field('paymentDate'), '2026-10-03');
      expect(field('ocrText')!.length, 4000);
      expect(field('editSignals'), 'Software de edición: GIMP;Otra');
      expect(raw, contains('name="file"; filename="comprobante.webp"'));
    });

    test('UploadVoucher sin OCR ni señales no manda esos campos', () async {
      final r = ApiPaymentsRepository(
        api({'responseCode': '00', 'chargeData': chargeJson}),
      );
      await r.uploadVoucher('c1', _form(150), _file);
      final raw = utf8.decode(requests.single.bodyBytes);
      expect(raw, isNot(contains('name="ocrText"')));
      expect(raw, isNot(contains('name="editSignals"')));
    });

    test('GetPendingReviews y ReviewVoucher', () async {
      final r = ApiPaymentsRepository(
        api({'responseCode': '00', 'chargeData': []}),
      );
      await r.reviewQueue();
      expect(requests.last.url.path, '/api/Payment/GetPendingReviews');
      expect(requests.last.url.queryParameters['page'], '1');

      body = {'responseCode': '00', 'chargeData': chargeJson};
      await r.reviewVoucher('v9', approve: false, comment: ' Ilegible 123 ');
      expect(requests.last.url.path, '/api/Payment/ReviewVoucher');
      expect(sent(), {
        'voucherId': 'v9',
        'decision': 'X',
        'comment': 'Ilegible 123',
      });
      await r.reviewVoucher('v9', approve: true);
      expect(sent(), {'voucherId': 'v9', 'decision': 'A'});
    });

    test('GetChargeData con filtros y CancelCharge', () async {
      final r = ApiPaymentsRepository(
        api({'responseCode': '00', 'chargeData': [], 'hasNext': false}),
      );
      await r.charges(
        status: ChargeStatus.pending,
        type: ChargeType.enrollment,
        period: '2026-10',
        search: ' luis ',
      );
      final q = requests.last.url.queryParameters;
      expect(requests.last.url.path, '/api/Payment/GetChargeData');
      expect(q['status'], 'P');
      expect(q['type'], 'I');
      expect(q['period'], '2026-10');
      expect(q['search'], 'luis');
      expect(q['pageSize'], '100');

      body = {'responseCode': '00', 'chargeData': chargeJson};
      await r.cancelCharge('c1');
      expect(requests.last.url.path, '/api/Payment/CancelCharge');
      expect(sent(), {'chargeId': 'c1'});
    });

    test('GetInsolventUsers y NotifyInsolvents', () async {
      final r = ApiPaymentsRepository(
        api({
          'responseCode': '00',
          'userData': [
            {
              'userId': 'u2',
              'name': 'Luis Istacuy',
              'email': 'luis@correo.com',
              'overdueAmount': 300.0,
              'overdueCharges': 2,
              'oldestDueDate': '2026-09-15',
              'lastReminderAt': null,
              'dependents': [
                {'name': 'Pablo', 'categoryId': 2, 'categoryName': 'Infantil'},
              ],
            },
          ],
          'page': 1,
          'pageSize': 100,
          'hasNext': false,
          'totalRecords': 1,
        }),
      );
      final page = await r.insolventUsers(categoryId: 2, search: 'luis');
      expect(requests.last.url.path, '/api/Payment/GetInsolventUsers');
      expect(requests.last.url.queryParameters['categoryId'], '2');
      expect(requests.last.url.queryParameters['search'], 'luis');
      final u = page.users.single;
      expect(u.overdueAmount, 300);
      expect(u.overdueCharges, 2);
      expect(u.dependents.single.categoryName, 'Infantil');
      expect(page.totalRecords, 1);

      body = {'responseCode': '00', 'notifiedCount': 5, 'skippedCount': 2};
      final all = await r.notifyInsolvents(message: ' Paguen ');
      expect(requests.last.url.path, '/api/Payment/NotifyInsolvents');
      expect(sent(), {'userIds': null, 'message': 'Paguen'});
      expect((all.notified, all.skipped), (5, 2));

      await r.notifyInsolvents(userIds: ['u2', 'u3']);
      expect(sent(), {
        'userIds': ['u2', 'u3'],
      });
    });

    test('GetSolvencyReport', () async {
      final r = ApiPaymentsRepository(
        api({
          'responseCode': '00',
          'reportData': {
            'period': '2026-10',
            'approvedUsers': 40,
            'solventUsers': 35,
            'insolventUsers': 5,
            'pendingValidationUsers': 3,
            'overdueAmount': 750.0,
            'collectedThisPeriod': 4500.0,
            'inReviewAmount': 300.0,
          },
        }),
      );
      final rep = await r.solvencyReport();
      expect(requests.single.url.path, '/api/Payment/GetSolvencyReport');
      expect(rep.insolventUsers, 5);
      expect(rep.collectedThisPeriod, 4500);
      expect(rep.pendingValidationUsers, 3);
    });

    test('configuración: leer y guardar', () async {
      final r = ApiSettingsRepository(
        api({
          'responseCode': '00',
          'settingsData': {
            'defaultEnrollmentFee': 250.0,
            'defaultMonthlyFee': 150.0,
            'dueDay': 15,
            'whatsappNumber': '+502 5555-1234',
            'contactName': 'Tesorería del club',
          },
        }),
      );
      final s = await r.paymentSettings();
      expect(requests.last.url.path, '/api/Settings/GetPaymentSettings');
      expect(s.whatsappNumber, '50255551234');
      expect(s.defaultMonthlyFee, 150);
      expect(s.hasContact, isTrue);

      await r.updatePaymentSettings(
        const PaymentSettings(
          defaultEnrollmentFee: 300,
          defaultMonthlyFee: 175,
          dueDay: 10,
          whatsappNumber: '',
          contactName: 'Tesorería',
        ),
      );
      expect(requests.last.url.path, '/api/Settings/UpdatePaymentSettings');
      expect(sent(), {
        'defaultEnrollmentFee': 300.0,
        'defaultMonthlyFee': 175.0,
        'dueDay': 10,
        'whatsappNumber': '',
        'contactName': 'Tesorería',
      });
    });

    test('validación de usuarios (Billing)', () async {
      final billingData = {
        'responseCode': '00',
        'billingData': {
          'userId': 'u7',
          'status': 'A',
          'enrollmentFee': 250.0,
          'monthlyFee': 150.0,
          'approvedBy': 'Diego Alvarez',
          'approvedAt': '2026-10-01T10:00:00Z',
          'solvent': true,
          'overdueAmount': 0,
        },
      };
      final r = ApiBillingRepository(
        api({
          'responseCode': '00',
          'userData': [
            {
              'userId': 'u7',
              'email': 'ana@correo.com',
              'firstName': 'Ana',
              'firstLastName': 'López',
              'createdAt': '2026-09-28T10:00:00Z',
              'dependentsCount': 2,
            },
          ],
        }),
      );
      final pending = await r.pendingUsers(search: 'ana');
      expect(requests.last.url.path, '/api/Billing/GetPendingUsers');
      expect(requests.last.url.queryParameters['search'], 'ana');
      expect(pending.single.name, 'Ana López');
      expect(pending.single.dependentsCount, 2);

      body = billingData;
      final b = await r.validateUser('u7', enrollmentFee: 250, monthlyFee: 150);
      expect(requests.last.url.path, '/api/Billing/ValidateUser');
      expect(sent(), {
        'userId': 'u7',
        'enrollmentFee': 250.0,
        'monthlyFee': 150.0,
      });
      expect(b.status, BillingStatus.active);
      expect(b.approvedBy, 'Diego Alvarez');

      await r.updateUserFees('u7', monthlyFee: 175);
      expect(requests.last.url.path, '/api/Billing/UpdateUserFees');
      expect(sent(), {'userId': 'u7', 'monthlyFee': 175.0});

      await r.userBilling('u7');
      expect(requests.last.method, 'GET');
      expect(requests.last.url.path, '/api/Billing/GetUserBilling/u7');
    });

    test('notificaciones', () async {
      final r = ApiNotificationRepository(
        api({
          'responseCode': '00',
          'notificationData': [
            {
              'notificationId': 'n1',
              'type': 'VOUCHER_SUBMITTED',
              'title': 'Nuevo comprobante',
              'body': 'Luis envió un comprobante',
              'data': {'voucherId': 'v1', 'chargeId': 'c1'},
              'createdAt': '2026-10-03T15:00:00Z',
              'readAt': null,
            },
          ],
          'unreadCount': 1,
          'hasNext': false,
        }),
      );
      final page = await r.myNotifications(unreadOnly: true);
      final q = requests.last.url.queryParameters;
      expect(requests.last.url.path, '/api/Notification/GetMyNotifications');
      expect(q['unreadOnly'], 'true');
      expect(q['pageSize'], '30');
      expect(page.unreadCount, 1);
      expect(page.items.single.unread, isTrue);
      expect(page.items.single.data['chargeId'], 'c1');

      body = {'responseCode': '00', 'unreadCount': 0};
      expect(await r.markAsRead(ids: ['n1']), 0);
      expect(requests.last.url.path, '/api/Notification/MarkAsRead');
      expect(sent(), {
        'notificationIds': ['n1'],
      });
      await r.markAsRead(all: true);
      expect(sent(), {'all': true});
    });

    test('jugadores: filtros a la API y datos del padre', () async {
      final r = ApiAdminRepository(
        api({
          'responseCode': '00',
          'dependentData': [
            {
              'dependentId': 'd1',
              'name': 'Pablo',
              'lastName': 'Istacuy',
              'cui': '1234567890101',
              'categoryId': 2,
              'categoryName': 'Infantil',
              'parentUserId': 'u2',
              'parentName': 'Luis Istacuy',
              'parentSolvent': false,
            },
          ],
          'hasNext': false,
        }),
      );
      final p = (await r.players(categoryId: 2, search: ' pablo ')).single;
      final q = requests.single.url.queryParameters;
      expect(
        requests.single.url.path,
        '/api/Dependent/GetDependentDataByCategory',
      );
      expect(q['categoryId'], '2');
      expect(q['search'], 'pablo');
      expect(p.dependentId, 'd1');
      expect(p.parentName, 'Luis Istacuy');
      expect(p.parentSolvent, isFalse);
    });

    test('errores del contrato se muestran en español', () async {
      for (final (raw, expected) in [
        ('MONTO NO COINCIDE CON EL COBRO', 'igual al del cobro'),
        ('REFERENCIA YA UTILIZADA', 'ya se usó'),
        ('COMPROBANTE DUPLICADO', 'ya se había enviado'),
        ('PERFIL PENDIENTE DE VALIDACION', 'en configuración'),
        ('NO SE PUEDE ASIGNAR SUPER_ADMIN', 'super admin'),
      ]) {
        final r = ApiPaymentsRepository(
          ApiClient(
            baseUrl: 'http://api.test',
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({'responseCode': '30', 'message': raw}),
                400,
              ),
            ),
          ),
        );
        await expectLater(
          r.myCharges(),
          throwsA(
            isA<PaymentsException>().having(
              (e) => e.message,
              'message',
              contains(expected),
            ),
          ),
          reason: raw,
        );
      }
    });
  });
}
