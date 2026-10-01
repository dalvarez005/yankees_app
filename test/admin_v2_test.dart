import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/app/app_theme.dart';
import 'package:yankees/core/access/permissions.dart';
import 'package:yankees/features/admin/data/admin_repository.dart';
import 'package:yankees/features/admin/presentation/players_page.dart';
import 'package:yankees/features/auth/data/app_user.dart';
import 'package:yankees/features/billing/data/billing_repository.dart';
import 'package:yankees/features/billing/presentation/pending_users_page.dart';
import 'package:yankees/features/categories/data/category_repository.dart';
import 'package:yankees/features/payments/data/payment_models.dart';
import 'package:yankees/features/payments/data/payments_repository.dart';
import 'package:yankees/features/payments/data/settings_repository.dart';
import 'package:yankees/features/payments/presentation/admin/insolvents_page.dart';

AppUser _admin(Set<String> permissions) => AppUser(
  id: 'a1',
  email: 'admin@test.com',
  firstName: 'Admin',
  firstLastName: 'X',
  roleName: 'Tesorería',
  permissions: permissions,
);

/// Registra los filtros que se mandan a la API.
class _FakePlayers extends UnavailableAdminRepository {
  final calls = <(int?, String?)>[];

  @override
  Future<List<Player>> players({
    int? categoryId,
    String? search,
    int? page,
    int pageSize = 100,
  }) async {
    if ((page ?? 1) > 1) return const [];
    calls.add((categoryId, search));
    return [
      const Player(
        name: 'Pablo',
        lastName: 'Istacuy',
        cui: '1234567890101',
        categoryId: 2,
        categoryName: 'Preinfantil',
        parentName: 'Luis Istacuy',
        parentSolvent: false,
      ),
      if (categoryId == null)
        const Player(
          name: 'Sara',
          lastName: 'Gómez',
          categoryId: 3,
          categoryName: 'Infantil',
          parentName: 'Ana Gómez',
          parentSolvent: true,
        ),
    ];
  }
}

/// Registra los recordatorios enviados.
class _SpyInsolvents extends MockPaymentsRepository {
  _SpyInsolvents() : super(latency: Duration.zero);
  final notified = <(List<String>?, String?)>[];

  @override
  Future<NotifyResult> notifyInsolvents({
    List<String>? userIds,
    String? message,
  }) async {
    notified.add((userIds, message));
    return NotifyResult(notified: userIds?.length ?? 3, skipped: 1);
  }
}

Widget _app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

/// Pantalla alta: las listas perezosas construyen todo el contenido.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    CategoryRepository.instance = MockCategoryRepository(
      latency: Duration.zero,
    );
    SettingsRepository.instance = MockSettingsRepository(
      latency: Duration.zero,
    );
    BillingRepository.instance = MockBillingRepository(latency: Duration.zero);
  });

  group('Jugadores', () {
    testWidgets('filtra por categoría y búsqueda en la API', (tester) async {
      final repo = _FakePlayers();
      AdminRepository.instance = repo;
      await tester.pumpWidget(
        _app(PlayersPage(user: _admin({Permissions.playersView}))),
      );
      await tester.pumpAndSettle();
      expect(repo.calls.last, (null, ''));
      expect(find.text('Pablo Istacuy'), findsOneWidget);
      expect(find.text('Sara Gómez'), findsOneWidget);
      expect(find.text('Insolvente'), findsOneWidget);
      expect(find.text('Solvente'), findsOneWidget);
      expect(find.textContaining('Luis Istacuy'), findsOneWidget);

      // Filtros → categoría (id 2 = Preinfantil en el mock) → Aplicar.
      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Preinfantil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar 1 filtro'));
      await tester.pumpAndSettle();
      expect(find.text('Filtros · 1'), findsOneWidget);
      expect(repo.calls.last, (2, ''));
      expect(find.text('Sara Gómez'), findsNothing);

      await tester.enterText(find.byType(TextField), 'pablo');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(repo.calls.last, (2, 'pablo'));
    });

    testWidgets('sin jugadores.ver no hay acceso', (tester) async {
      AdminRepository.instance = _FakePlayers();
      await tester.pumpWidget(
        _app(PlayersPage(user: _admin({Permissions.usersView}))),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No tienes permiso para ver esta sección.'),
        findsOneWidget,
      );
    });
  });

  group('Insolventes', () {
    late _SpyInsolvents repo;

    setUp(() {
      repo = _SpyInsolvents();
      PaymentsRepository.instance = repo;
    });

    Future<void> pump(WidgetTester tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _app(InsolventsPage(user: _admin({Permissions.paymentsManage}))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('resumen y notificar a todos con mensaje', (tester) async {
      await pump(tester);
      expect(find.textContaining('Resumen'), findsOneWidget);
      expect(find.text('Luis Istacuy'), findsOneWidget);

      await tester.tap(find.text('Notificar a todos los insolventes'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Pagar antes del 20');
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      // Confirmación.
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();

      expect(repo.notified.single, (null, 'Pagar antes del 20'));
      expect(find.textContaining('Se notificó a 3 usuarios.'), findsOneWidget);
      expect(find.textContaining('1 omitido'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('selección múltiple y notificar seleccionados', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Luis Istacuy'));
      await tester.pump();
      expect(find.text('Notificar seleccionados (1)'), findsOneWidget);

      await tester.tap(find.text('Notificar seleccionados (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();

      expect(repo.notified.single.$1, ['u2']);
      expect(repo.notified.single.$2, '');
      // Tras enviar se limpia la selección.
      expect(find.text('Notificar a todos los insolventes'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('cancelar la confirmación no notifica', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Notificar a todos los insolventes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.notified, isEmpty);
    });

    testWidgets('filtro por categoría', (tester) async {
      await pump(tester);
      // Luis tiene un hijo en la categoría 2 (Preinfantil); Ana en 2 y 3.
      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Infantil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar 1 filtro'));
      await tester.pumpAndSettle();
      expect(find.text('Luis Istacuy'), findsNothing);
      expect(find.text('Ana Gómez'), findsOneWidget);
    });
  });

  group('Usuarios por validar', () {
    testWidgets('valida con las cuotas sugeridas', (tester) async {
      await tester.pumpWidget(
        _app(PendingUsersPage(user: _admin({Permissions.usersValidate}))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lucía Ramírez'));
      await tester.pumpAndSettle();

      // Prellenado con la configuración por defecto (250 / 150).
      expect(find.text('250'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Validar usuario');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Validar'));
      await tester.pumpAndSettle();

      expect(find.text('Nadie esperando'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}
