import '../../../core/network/api_client.dart';
import 'dependent.dart';

class DependentException implements Exception {
  const DependentException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Hijos del usuario con sesión. La API los toma del token: no se manda
/// el userId.
abstract class DependentRepository {
  static DependentRepository instance = MockDependentRepository();

  Future<List<Dependent>> list();
  Future<Dependent> add(DependentInput input);
  Future<Dependent> update(String id, DependentInput input);
  Future<void> remove(String id);
}

class ApiDependentRepository implements DependentRepository {
  ApiDependentRepository(this._api);
  final ApiClient _api;

  static const _manage = '/api/Dependent/ManageDependent';

  @override
  Future<List<Dependent>> list() async {
    final json = await _call(
      () => _api.get(
        '/api/Dependent/GetDependentDataForUser?page=1&pageSize=100',
      ),
    );
    final items = json['dependentData'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(Dependent.fromJson)
        .toList();
  }

  @override
  Future<Dependent> add(DependentInput input) =>
      _save({'typeOperation': 'A', 'dependentData': input.toJson()});

  @override
  Future<Dependent> update(String id, DependentInput input) => _save({
    'typeOperation': 'U',
    'dependentData': {'dependentId': id, ...input.toJson()},
  });

  @override
  Future<void> remove(String id) async {
    await _call(
      () => _api.post(_manage, {
        'typeOperation': 'D',
        'dependentData': {'dependentId': id},
      }),
    );
  }

  Future<Dependent> _save(Map<String, dynamic> body) async {
    final json = await _call(() => _api.post(_manage, body));
    return Dependent.fromJson(
      json['dependentData'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Errores de red/HTTP y respuestas 200 con responseCode distinto de
  /// "00" (p. ej. CUI repetido) se convierten en mensajes para el usuario.
  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    final Map<String, dynamic> json;
    try {
      json = await request();
    } on ApiException catch (e) {
      throw DependentException(e.message);
    }
    final code = json['responseCode']?.toString();
    if (code != null && code != '00') {
      final message = json['responseMessage']?.toString() ?? '';
      throw DependentException(
        message.isEmpty
            ? 'No se pudo completar la operación.'
            : ApiClient.translate(message),
      );
    }
    return json;
  }
}

/// En memoria, para `USE_MOCK` y pruebas de UI.
class MockDependentRepository implements DependentRepository {
  MockDependentRepository({this.latency = const Duration(milliseconds: 500)});

  /// En widget tests conviene [Duration.zero] (el reloj es simulado).
  final Duration latency;
  final _items = <Dependent>[];
  var _seq = 0;

  Future<void> _latency() => Future.delayed(latency);

  @override
  Future<List<Dependent>> list() async {
    await _latency();
    return List.unmodifiable(_items);
  }

  @override
  Future<Dependent> add(DependentInput input) async {
    await _latency();
    if (_items.any((d) => d.cui == input.cui)) {
      throw const DependentException('Ese CUI ya está registrado.');
    }
    final created = _fromInput('${++_seq}', input);
    _items.add(created);
    return created;
  }

  @override
  Future<Dependent> update(String id, DependentInput input) async {
    await _latency();
    final i = _items.indexWhere((d) => d.id == id);
    if (i < 0) throw const DependentException('No se encontró el registro.');
    return _items[i] = _fromInput(id, input);
  }

  @override
  Future<void> remove(String id) async {
    await _latency();
    _items.removeWhere((d) => d.id == id);
  }

  Dependent _fromInput(String id, DependentInput input) => Dependent(
    id: id,
    cui: input.cui,
    firstName: input.firstName,
    secondName: input.secondName,
    firstLastName: input.firstLastName,
    secondLastName: input.secondLastName,
    categoryId: input.categoryId,
    age: input.age,
  );
}
