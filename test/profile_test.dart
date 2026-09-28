import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/app/app_theme.dart';
import 'package:yankees/features/auth/data/app_user.dart';
import 'package:yankees/features/auth/data/auth_repository.dart';
import 'package:yankees/features/profile/data/profile_review_store.dart';
import 'package:yankees/features/profile/presentation/confirm_profile_page.dart';

const _googleJoker = AppUser(
  id: 'g1',
  email: 'joker12@gmail.com',
  firstName: 'Joker',
  firstLastName: 'GOOGLE',
  role: UserRole.parent,
);

const _real = AppUser(
  id: 'u1',
  email: 'ana@test.com',
  firstName: 'Ana',
  firstLastName: 'Gómez',
  role: UserRole.parent,
);

/// Repositorio que devuelve un perfil fijo y registra lo guardado.
class _FakeAuth extends MockAuthRepository {
  _FakeAuth(this.profile);
  AppUser profile;
  ProfileInput? saved;

  @override
  Future<AppUser> fetchProfile() async => profile;

  @override
  Future<AppUser> updateProfile(ProfileInput input) async {
    saved = input;
    return profile = AppUser(
      id: profile.id,
      email: profile.email,
      role: profile.role,
      firstName: input.firstName,
      secondName: input.secondName,
      firstLastName: input.firstLastName,
      secondLastName: input.secondLastName,
    );
  }
}

void main() {
  group('ProfileReviewStore', () {
    test('apellido "GOOGLE" o correo como nombre son de relleno', () {
      expect(ProfileReviewStore.hasPlaceholderData(_googleJoker), isTrue);
      expect(
        ProfileReviewStore.hasPlaceholderData(
          const AppUser(
            id: 'x',
            email: 'a@b.com',
            firstName: 'a@b.com',
            firstLastName: 'Pérez',
            role: UserRole.parent,
          ),
        ),
        isTrue,
      );
      expect(ProfileReviewStore.hasPlaceholderData(_real), isFalse);
    });

    test('pide revisión la primera vez y no después de confirmar', () async {
      final store = MemoryProfileReviewStore();
      expect(await store.needsReview(_real), isTrue);
      await store.markReviewed(_real.id);
      expect(await store.needsReview(_real), isFalse);
    });

    test('datos de relleno se piden aunque ya haya confirmado', () async {
      final store = MemoryProfileReviewStore()..reviewed.add(_googleJoker.id);
      expect(await store.needsReview(_googleJoker), isTrue);
    });
  });

  group('ConfirmProfilePage', () {
    late _FakeAuth auth;

    setUp(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      ProfileReviewStore.instance = MemoryProfileReviewStore();
    });

    Future<void> open(WidgetTester tester, AppUser user) async {
      auth = _FakeAuth(user);
      AuthRepository.instance = auth;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ConfirmProfilePage(user: user),
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('INICIO')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'cuenta de Google con apellido de relleno obliga a escribirlo',
      (tester) async {
        await open(tester, _googleJoker);

        expect(find.text('Confirma tus datos'), findsOneWidget);
        expect(find.text('joker12@gmail.com'), findsOneWidget);
        expect(find.text('GOOGLE'), findsNothing);

        await tester.ensureVisible(find.text('Confirmar y continuar'));
        await tester.tap(find.text('Confirmar y continuar'));
        await tester.pumpAndSettle();
        expect(find.text('El apellido es obligatorio'), findsOneWidget);
        expect(auth.saved, isNull);
      },
    );

    testWidgets('al confirmar guarda, marca revisado y entra', (tester) async {
      await open(tester, _googleJoker);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Carlos');
      await tester.enterText(fields.at(2), 'Pérez');
      await tester.ensureVisible(find.text('Confirmar y continuar'));
      await tester.tap(find.text('Confirmar y continuar'));
      await tester.pumpAndSettle();

      expect(auth.saved!.firstName, 'Carlos');
      expect(auth.saved!.firstLastName, 'Pérez');
      expect(
        await ProfileReviewStore.instance.isReviewed(_googleJoker.id),
        isTrue,
      );
      expect(find.text('INICIO'), findsOneWidget);
    });
  });
}
