import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/main.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// null = deshabilitado.
  VoidCallback? action(WidgetTester tester, String label) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, label))
      .onPressed;

  testWidgets('login: Ingresar se habilita con correo y contraseña válidos', (
    tester,
  ) async {
    await tester.pumpWidget(const YankeesApp());
    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(action(tester, 'Ingresar'), isNull);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ana@');
    await tester.pump();
    // El error se ve al escribir, sin tocar el botón.
    expect(find.text('Correo no válido'), findsOneWidget);
    expect(action(tester, 'Ingresar'), isNull);

    await tester.enterText(fields.at(0), 'ana@test.com');
    await tester.enterText(fields.at(1), '123');
    await tester.pump();
    expect(find.text('Mínimo 6 caracteres'), findsOneWidget);
    expect(action(tester, 'Ingresar'), isNull);

    await tester.enterText(fields.at(1), 'clave123');
    await tester.pump();
    expect(action(tester, 'Ingresar'), isNotNull);
  });

  testWidgets('registro: Crear cuenta se habilita al completar todo', (
    tester,
  ) async {
    await tester.pumpWidget(const YankeesApp());
    await tester.ensureVisible(find.text('Regístrate'));
    await tester.tap(find.text('Regístrate'));
    await tester.pumpAndSettle();
    expect(find.text('Atrás'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(action(tester, 'Crear cuenta'), isNull);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ana');
    await tester.enterText(fields.at(1), 'Gómez');
    await tester.enterText(fields.at(2), 'ana@test.com');
    await tester.enterText(fields.at(3), 'clave123');
    await tester.enterText(fields.at(4), 'otra123');
    await tester.pump();
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(action(tester, 'Crear cuenta'), isNull);

    await tester.enterText(fields.at(4), 'clave123');
    await tester.pump();
    expect(action(tester, 'Crear cuenta'), isNotNull);
  });
}
