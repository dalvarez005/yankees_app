import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yankees/core/network/api_client.dart';
import 'package:yankees/features/family/data/dependent.dart';
import 'package:yankees/features/family/data/dependent_repository.dart';

void main() {
  late List<http.Request> requests;

  ApiDependentRepository repo(http.Response Function(http.Request) handler) {
    requests = [];
    return ApiDependentRepository(
      ApiClient(
        baseUrl: 'http://api.test',
        client: MockClient((req) async {
          requests.add(req);
          return handler(req);
        }),
      ),
    );
  }

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  const input = DependentInput(
    cui: '1234567890101',
    firstName: 'Sofía',
    secondName: '',
    firstLastName: 'Castro',
    categoryId: 2,
  );

  Map<String, dynamic> dependentJson() => {
    'dependentId': 'd-1',
    'userId': 'u-1',
    'cui': '1234567890101',
    'firstName': 'Sofía',
    'secondName': null,
    'firstLastName': 'Castro',
    'secondLastName': null,
    'categoryId': 2,
    'status': 'A',
  };

  test('list hace GET /api/Dependent y mapea los hijos', () async {
    final r = repo(
      (_) => json({
        'responseCode': '00',
        'dependentData': [dependentJson()],
      }),
    );
    final items = await r.list();

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/Dependent');
    expect(items.single.fullName, 'Sofía Castro');
    expect(items.single.formattedCui, '1234 56789 0101');
    expect(items.single.categoryId, 2);
  });

  test('list vacía', () async {
    final r = repo(
      (_) => json({
        'responseCode': '00',
        'responseMessage': 'SIN DEPENDIENTES',
        'dependentData': [],
      }),
    );
    expect(await r.list(), isEmpty);
  });

  test('add manda typeOperation A sin campos opcionales vacíos', () async {
    final r = repo(
      (_) => json({'responseCode': '00', 'dependentData': dependentJson()}),
    );
    final created = await r.add(input);

    expect(requests.single.url.path, '/api/Dependent/ManageDependent');
    expect(jsonDecode(requests.single.body), {
      'typeOperation': 'A',
      'dependentData': {
        'cui': '1234567890101',
        'firstName': 'Sofía',
        'firstLastName': 'Castro',
        'categoryId': 2,
      },
    });
    expect(created.id, 'd-1');
  });

  test('update manda U con dependentId', () async {
    final r = repo(
      (_) => json({'responseCode': '00', 'dependentData': dependentJson()}),
    );
    await r.update('d-1', input);
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['typeOperation'], 'U');
    expect(body['dependentData']['dependentId'], 'd-1');
  });

  test('remove manda D solo con el id', () async {
    final r = repo((_) => json({'responseCode': '00'}));
    await r.remove('d-1');
    expect(jsonDecode(requests.single.body), {
      'typeOperation': 'D',
      'dependentData': {'dependentId': 'd-1'},
    });
  });

  test('CUI repetido (200 con código 39) se muestra en español', () async {
    final r = repo(
      (_) => json({
        'responseCode': '39',
        'responseMessage': 'CUI YA ASOCIADO A UN DEPENDIENTE ACTIVO',
      }),
    );
    expect(
      () => r.add(input),
      throwsA(
        isA<DependentException>().having(
          (e) => e.message,
          'message',
          'Ese CUI ya está registrado.',
        ),
      ),
    );
  });

  test('sin conexión da mensaje claro', () async {
    final r = repo((_) => throw http.ClientException('offline'));
    expect(
      r.list,
      throwsA(
        isA<DependentException>().having(
          (e) => e.message,
          'message',
          contains('No se pudo conectar'),
        ),
      ),
    );
  });
}
