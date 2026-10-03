import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/app/app_theme.dart';
import 'package:yankees/features/auth/data/app_user.dart';
import 'package:yankees/features/categories/data/category_repository.dart';
import 'package:yankees/features/family/data/dependent.dart';
import 'package:yankees/features/family/data/dependent_repository.dart';
import 'package:yankees/features/family/presentation/family_page.dart';
import 'package:yankees/features/notifications/data/notification_repository.dart';
import 'package:yankees/features/payments/data/payment_models.dart';
import 'package:yankees/features/payments/data/payments_repository.dart';

const _user = AppUser(
  id: 'u1',
  email: 'ana@test.com',
  firstName: 'Ana',
  firstLastName: 'Gómez',
  roleName: 'USER_BASE',
  permissions: {'hijos.gestionar_propios'},
);

Widget _app() => MaterialApp(
  theme: AppTheme.light,
  home: const FamilyPage(user: _user),
);

/// Saldo fijo y sin cobros.
class _FixedBalance extends MockPaymentsRepository {
  _FixedBalance(this.balance) : super(latency: Duration.zero);
  final AccountBalance balance;

  @override
  Future<AccountBalance> myBalance() async => balance;

  @override
  Future<List<Charge>> myCharges() async => const [];
}

/// Pantalla alta: los cobros de la familia empujan el estado vacío hacia
/// abajo.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    DependentRepository.instance = MockDependentRepository(
      latency: Duration.zero,
    );
    PaymentsRepository.instance = MockPaymentsRepository(
      latency: Duration.zero,
    );
    CategoryRepository.instance = MockCategoryRepository(
      latency: Duration.zero,
    );
    NotificationRepository.instance = MockNotificationRepository(
      latency: Duration.zero,
    );
  });

  testWidgets('sin hijos muestra el estado vacío', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Hola, Ana Gómez'), findsOneWidget);
    expect(find.text('Aún no registras a tus hijos'), findsOneWidget);
    expect(find.text('Agregar hijo'), findsOneWidget);
  });

  testWidgets('lista a los hijos con CUI y categoría', (tester) async {
    await tester.runAsync(
      () => DependentRepository.instance.add(
        DependentInput(
          cui: '1234567890101',
          firstName: 'Sofía',
          firstLastName: 'Castro',
          birthDate: DateTime(2018, 1, 15),
        ),
      ),
    );
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Sofía Castro'), findsOneWidget);
    final age = ageAt(DateTime(2018, 1, 15), DateTime.now());
    expect(find.text('$age años · CUI 1234 56789 0101'), findsOneWidget);
    // La categoría viene del catálogo (id 2 = Preinfantil en el mock).
    expect(find.text('Preinfantil'), findsOneWidget);
    expect(find.text('Tienes 1 hijo registrado.'), findsOneWidget);
  });

  testWidgets('muestra el saldo: insolvente con el monto vencido', (
    tester,
  ) async {
    PaymentsRepository.instance = _FixedBalance(
      const AccountBalance(solvent: false, totalOwed: 400, overdueAmount: 150),
    );
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('INSOLVENTE'), findsOneWidget);
    expect(find.text('Q 150.00 vencido'), findsOneWidget);
    expect(find.text('Total por pagar Q 400.00'), findsOneWidget);
  });

  testWidgets('al día muestra Solvente', (tester) async {
    PaymentsRepository.instance = _FixedBalance(
      const AccountBalance(solvent: true),
    );
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Solvente'), findsOneWidget);
    expect(find.text('Estás al día'), findsOneWidget);
  });

  testWidgets(
    'el formulario pide la fecha y muestra la categoría solo como información',
    (tester) async {
      _tall(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar hijo'));
      await tester.pumpAndSettle();

      expect(find.text('Fecha de nacimiento'), findsOneWidget);
      expect(find.text('Selecciona la fecha'), findsOneWidget);
      expect(find.text('Se asigna al guardar'), findsOneWidget);
    },
  );

  testWidgets('el formulario valida CUI, nombre y apellido', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar hijo'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '12345');
    await tester.ensureVisible(find.text('Agregar'));
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();

    expect(find.text('El CUI debe tener 13 dígitos'), findsOneWidget);
    expect(find.text('El nombre es obligatorio'), findsOneWidget);
    expect(find.text('El apellido es obligatorio'), findsOneWidget);
  });
}
