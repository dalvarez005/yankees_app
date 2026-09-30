import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/app/app_theme.dart';
import 'package:yankees/features/auth/data/app_user.dart';
import 'package:yankees/features/categories/data/category_repository.dart';
import 'package:yankees/features/family/data/dependent.dart';
import 'package:yankees/features/family/data/dependent_repository.dart';
import 'package:yankees/features/family/presentation/family_page.dart';

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

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    DependentRepository.instance = MockDependentRepository(
      latency: Duration.zero,
    );
    CategoryRepository.instance = MockCategoryRepository(
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
        const DependentInput(
          cui: '1234567890101',
          firstName: 'Sofía',
          firstLastName: 'Castro',
          categoryId: 2,
        ),
      ),
    );
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Sofía Castro'), findsOneWidget);
    expect(find.text('CUI 1234 56789 0101'), findsOneWidget);
    // La categoría viene del catálogo (id 2 = Preinfantil en el mock).
    expect(find.text('Preinfantil'), findsOneWidget);
    expect(find.text('Tienes 1 hijo registrado.'), findsOneWidget);
  });

  testWidgets('el formulario ofrece solo categorías activas', (tester) async {
    await tester.runAsync(
      () => CategoryRepository.instance.deactivate(1), // Moscos
    );
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar hijo'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Selecciona'));
    await tester.tap(find.text('Selecciona'));
    await tester.pumpAndSettle();

    expect(find.text('Infantil'), findsWidgets);
    expect(find.text('Moscos'), findsNothing);
  });

  testWidgets('el formulario valida CUI, nombre, apellido y categoría', (
    tester,
  ) async {
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
    expect(find.text('Elige una categoría'), findsOneWidget);
  });
}
