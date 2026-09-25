import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/main.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('muestra el login y valida campos vacíos', (tester) async {
    await tester.pumpWidget(const YankeesApp());
    expect(find.text('Bienvenido'), findsOneWidget);

    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    expect(find.text('Ingresa tu correo'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
  });
}
