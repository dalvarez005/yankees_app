import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/app/home.dart';
import 'package:yankees/core/access/permissions.dart';
import 'package:yankees/features/admin/presentation/admin_home_page.dart';
import 'package:yankees/features/auth/data/app_user.dart';
import 'package:yankees/features/auth/data/auth_repository.dart';
import 'package:yankees/features/billing/data/billing_models.dart';
import 'package:yankees/features/billing/data/billing_repository.dart';
import 'package:yankees/features/billing/presentation/pending_profile_page.dart';
import 'package:yankees/features/categories/data/category_repository.dart';
import 'package:yankees/features/family/data/dependent_repository.dart';
import 'package:yankees/features/family/presentation/family_page.dart';
import 'package:yankees/features/notifications/data/notification_repository.dart';
import 'package:yankees/features/payments/data/payments_repository.dart';
import 'package:yankees/features/payments/data/settings_repository.dart';
import 'package:yankees/main.dart';

AppUser _parent(BillingStatus? status) => AppUser(
  id: 'u1',
  email: 'ana@test.com',
  firstName: 'Ana',
  firstLastName: 'Gómez',
  roleName: 'USER_BASE',
  permissions: const {Permissions.ownDependents},
  billing: status == null ? null : Billing(status: status),
);

/// `/me` devuelve lo que se le indique.
class _FakeAuth extends MockAuthRepository {
  _FakeAuth(this.profile);
  AppUser profile;
  var fetches = 0;

  @override
  Future<AppUser> fetchProfile() async {
    fetches++;
    return profile;
  }
}

void main() {
  group('billing en AppUser', () {
    test('se guarda en la sesión y se recupera', () {
      final u = AppUser(
        id: 'u1',
        email: 'a@b.com',
        firstName: 'A',
        firstLastName: 'B',
        billing: const Billing(
          status: BillingStatus.active,
          enrollmentFee: 250,
          monthlyFee: 150,
          solvent: false,
          overdueAmount: 150,
        ),
      );
      final back = AppUser.fromJson(jsonDecode(jsonEncode(u.toJson())));
      expect(back.billing!.status, BillingStatus.active);
      expect(back.billing!.monthlyFee, 150);
      expect(back.billing!.solvent, isFalse);
      expect(back.billing!.overdueAmount, 150);
    });

    test('sesiones viejas sin billing no quedan bloqueadas', () {
      final old = AppUser.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'firstName': 'A',
        'firstLastName': 'B',
        'permissions': ['hijos.gestionar_propios'],
      });
      expect(old.billing, isNull);
      expect(old.awaitingValidation, isFalse);
    });

    test('montos null con perfil pendiente', () {
      final b = Billing.fromJson({
        'status': 'P',
        'enrollmentFee': null,
        'monthlyFee': null,
        'solvent': true,
        'overdueAmount': 0,
      });
      expect(b.pending, isTrue);
      expect(b.enrollmentFee, isNull);
    });
  });

  group('inicio según el perfil de cobro', () {
    test('P → pantalla de espera; A o sin dato → Mi familia', () {
      expect(
        homePageFor(_parent(BillingStatus.pending)),
        isA<PendingProfilePage>(),
      );
      expect(homePageFor(_parent(BillingStatus.active)), isA<FamilyPage>());
      expect(homePageFor(_parent(null)), isA<FamilyPage>());
    });

    test('admin exento aunque figure pendiente', () {
      const admin = AppUser(
        id: 'a1',
        email: 'admin@test.com',
        firstName: 'Admin',
        firstLastName: 'X',
        roleName: 'Tesorería',
        permissions: {Permissions.paymentsReview},
        billing: Billing(status: BillingStatus.pending),
      );
      expect(admin.awaitingValidation, isFalse);
      expect(homePageFor(admin), isA<AdminHomePage>());
    });
  });

  group('pantalla "Estamos configurando tu perfil"', () {
    late _FakeAuth auth;

    setUp(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      auth = _FakeAuth(_parent(BillingStatus.pending));
      AuthRepository.instance = auth;
      SettingsRepository.instance = MockSettingsRepository(
        latency: Duration.zero,
      );
      PaymentsRepository.instance = MockPaymentsRepository(
        latency: Duration.zero,
      );
      DependentRepository.instance = MockDependentRepository(
        latency: Duration.zero,
      );
      CategoryRepository.instance = MockCategoryRepository(
        latency: Duration.zero,
      );
      NotificationRepository.instance = MockNotificationRepository(
        latency: Duration.zero,
      );
      BillingRepository.instance = MockBillingRepository(
        latency: Duration.zero,
      );
    });

    testWidgets('al restaurar sesión pendiente no deja avanzar', (
      tester,
    ) async {
      await tester.pumpWidget(
        YankeesApp(initialUser: _parent(BillingStatus.pending)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Estamos configurando tu perfil'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      // Hay WhatsApp configurado en el mock.
      expect(find.text('Escribir a Tesorería del club'), findsOneWidget);

      // Sigue pendiente: se queda y avisa.
      await tester.tap(find.text('Ya me validaron / Actualizar'));
      await tester.pumpAndSettle();
      expect(auth.fetches, 1);
      expect(find.byType(PendingProfilePage), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('cuando lo validan entra al inicio normal', (tester) async {
      await tester.pumpWidget(
        YankeesApp(initialUser: _parent(BillingStatus.pending)),
      );
      await tester.pumpAndSettle();

      auth.profile = _parent(BillingStatus.active);
      await tester.tap(find.text('Ya me validaron / Actualizar'));
      await tester.pumpAndSettle();
      expect(find.byType(PendingProfilePage), findsNothing);
      expect(find.byType(FamilyPage), findsOneWidget);
    });

    testWidgets('el admin nunca ve la pantalla de espera', (tester) async {
      const admin = AppUser(
        id: 'a1',
        email: 'admin@test.com',
        firstName: 'Admin',
        firstLastName: 'X',
        roleName: 'SUPER_ADMIN',
        permissions: {...Permissions.admin},
        billing: Billing(status: BillingStatus.notApplicable),
      );
      await tester.pumpWidget(const YankeesApp(initialUser: admin));
      await tester.pumpAndSettle();
      expect(find.byType(AdminHomePage), findsOneWidget);
      expect(find.text('Estamos configurando tu perfil'), findsNothing);
    });
  });
}
