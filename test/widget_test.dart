import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/features/profile/data/profile_review_store.dart';
import 'package:yankees/main.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    ProfileReviewStore.instance = MemoryProfileReviewStore();
  });

  testWidgets('muestra el login y valida campos vacíos', (tester) async {
    await tester.pumpWidget(const YankeesApp());
    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);

    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    expect(find.text('Ingresa tu correo'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
  });

  testWidgets('registro valida los campos obligatorios', (tester) async {
    await tester.pumpWidget(const YankeesApp());
    await tester.ensureVisible(find.text('Regístrate'));
    await tester.tap(find.text('Regístrate'));
    await tester.pumpAndSettle();
    expect(find.text('Atrás'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);

    await tester.ensureVisible(find.text('Crear cuenta').last);
    await tester.tap(find.text('Crear cuenta').last);
    await tester.pump();
    expect(find.text('El nombre es obligatorio'), findsOneWidget);
    expect(find.text('El apellido es obligatorio'), findsOneWidget);
    expect(find.text('Ingresa tu correo'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    expect(find.text('Confirma tu contraseña'), findsOneWidget);
  });
}
