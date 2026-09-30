import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yankees/app/app_theme.dart';
import 'package:yankees/core/access/permissions.dart';
import 'package:yankees/core/network/api_client.dart';
import 'package:yankees/features/admin/data/admin_repository.dart';
import 'package:yankees/features/admin/presentation/admin_home_page.dart';
import 'package:yankees/features/auth/data/app_user.dart';
import 'package:yankees/features/categories/data/category_repository.dart';

AppUser _user(Set<String> permissions, [String role = 'X']) => AppUser(
  id: 'u1',
  email: 'ana@test.com',
  firstName: 'Ana',
  firstLastName: 'Gómez',
  roleName: role,
  permissions: permissions,
);

void main() {
  group('AppUser', () {
    test('isAdmin con cualquier permiso de administración', () {
      expect(_user({Permissions.ownDependents}).isAdmin, isFalse);
      expect(_user({Permissions.usersView}).isAdmin, isTrue);
      expect(_user({Permissions.categoriesManage}).isAdmin, isTrue);
    });

    test('rol y permisos sobreviven al guardado de la sesión', () {
      final u = _user({Permissions.rolesManage}, 'Secretaría');
      final back = AppUser.fromJson(jsonDecode(jsonEncode(u.toJson())));
      expect(back.roleName, 'Secretaría');
      expect(back.can(Permissions.rolesManage), isTrue);
    });

    test('sesiones guardadas antes de los permisos no rompen', () {
      final old = AppUser.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'firstName': 'A',
        'firstLastName': 'B',
        'role': 'parent',
      });
      expect(old.permissions, isEmpty);
    });
  });

  group('AdminHomePage muestra solo las secciones permitidas', () {
    setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

    Future<void> pump(WidgetTester tester, Set<String> perms) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminHomePage(user: _user(perms, 'SUPER_ADMIN')),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('super admin ve todo', (tester) async {
      await pump(tester, {...Permissions.admin, Permissions.ownDependents});
      for (final s in [
        'Usuarios',
        'Roles y permisos',
        'Categorías',
        'Mi familia',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.text('Super admin'), findsOneWidget);
    });

    testWidgets('rol que solo gestiona usuarios', (tester) async {
      await pump(tester, {Permissions.usersView, Permissions.usersManage});
      expect(find.text('Usuarios'), findsOneWidget);
      expect(find.text('Roles y permisos'), findsNothing);
      expect(find.text('Categorías'), findsNothing);
      expect(find.text('Mi familia'), findsNothing);
    });

    testWidgets('rol sin permisos avisa', (tester) async {
      await pump(tester, {});
      expect(
        find.textContaining('no tiene permisos asignados'),
        findsOneWidget,
      );
    });
  });

  group('contratos con la API', () {
    late List<http.Request> requests;

    ApiClient api(Object body) {
      requests = [];
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

    test('crear rol: nombre por ManageRole y luego sus permisos', () async {
      final repo = ApiAdminRepository(
        api({
          'responseCode': '00',
          'roleData': {
            'roleId': 7,
            'roleName': 'Secretaría',
            'permissions': ['usuarios.ver'],
          },
        }),
      );
      final role = await repo.createRole(
        name: ' Secretaría ',
        permissions: {'usuarios.ver'},
      );
      expect(requests.map((r) => r.url.path), [
        '/api/Role/ManageRole',
        '/api/Role/UpdateRolePermissions',
      ]);
      expect(jsonDecode(requests.first.body), {
        'typeOperation': 'A',
        'roleData': {'roleName': 'Secretaría'},
      });
      expect(sent(), {
        'roleId': 7,
        'permissions': ['usuarios.ver'],
      });
      expect(role.permissions, {'usuarios.ver'});
    });

    test('editar solo permisos no renombra el rol', () async {
      final repo = ApiAdminRepository(
        api({'responseCode': '00', 'roleData': {}}),
      );
      await repo.updateRole(3, permissions: {});
      expect(requests.single.url.path, '/api/Role/UpdateRolePermissions');
      expect(sent(), {'roleId': 3, 'permissions': []});
    });

    test('roles: lista solo los activos con sus permisos', () async {
      final repo = ApiAdminRepository(
        api({
          'responseCode': '00',
          'roleData': [
            {
              'roleId': 2,
              'roleName': 'SUPER_ADMIN',
              'status': 'A',
              'permissions': ['roles.gestionar'],
              'userCount': 1,
            },
            {'roleId': 5, 'roleName': 'Viejo', 'status': 'I'},
          ],
        }),
      );
      final roles = await repo.roles();
      expect(requests.single.url.path, '/api/Role/GetRolePermissions');
      expect(roles.single.isSuperAdmin, isTrue);
      expect(roles.single.isSystem, isTrue);
    });

    test('cambiar rol y estado de un usuario', () async {
      final repo = ApiAdminRepository(
        api({'responseCode': '00', 'userData': {}}),
      );
      await repo.setUserRole('u9', 4);
      expect(requests.last.url.path, '/api/User/UpdateUserRole');
      expect(sent(), {'userId': 'u9', 'roleId': 4});
      await repo.setUserActive('u9', false);
      expect(requests.last.url.path, '/api/User/UpdateUserStatus');
      expect(sent(), {'userId': 'u9', 'status': 'I'});
    });

    test('buscar usuarios codifica el texto', () async {
      final repo = ApiAdminRepository(
        api({'responseCode': '00', 'userData': []}),
      );
      await repo.users(search: 'josé pérez');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/User/GetUserData');
      expect(requests.single.url.queryParameters['search'], 'josé pérez');
    });

    test('categorías: lista con activas e inactivas', () async {
      final repo = ApiCategoryRepository(
        api({
          'responseCode': '00',
          'categoryData': [
            {'categoryId': 1, 'categoryName': 'Moscos', 'status': 'A'},
            {'categoryId': 6, 'categoryName': 'Veteranos', 'status': 'I'},
          ],
        }),
      );
      final items = await repo.list();
      expect(requests.single.url.path, '/api/Category/GetCategoryData');
      expect(items.map((c) => (c.name, c.active)), [
        ('Moscos', true),
        ('Veteranos', false),
      ]);
    });

    test('categorías: renombrar manda categoryName', () async {
      final repo = ApiCategoryRepository(
        api({'responseCode': '00', 'categoryData': {}}),
      );
      await repo.rename(6, ' Juvenil B ');
      expect(sent(), {
        'typeOperation': 'U',
        'categoryData': {'categoryId': 6, 'categoryName': 'Juvenil B'},
      });
    });

    test('403 de la API se muestra en español', () async {
      final repo = ApiAdminRepository(
        ApiClient(
          baseUrl: 'http://api.test',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'responseCode': '03',
                'message': 'NO TIENE PERMISO PARA ESTA ACCION',
              }),
              403,
            ),
          ),
        ),
      );
      expect(
        repo.roles,
        throwsA(
          isA<AdminException>().having(
            (e) => e.message,
            'message',
            'No tienes permiso para esta acción.',
          ),
        ),
      );
    });
  });
}
