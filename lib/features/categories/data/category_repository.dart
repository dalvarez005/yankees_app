import '../../../core/network/api_client.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    this.active = true,
    this.ageFrom,
    this.ageTo,
  });

  final int id;
  final String name;

  /// Inactiva: no se ofrece para hijos nuevos, pero se conserva en los que
  /// ya la tienen.
  final bool active;

  /// Rango de edad (incluido) con el que la API asigna esta categoría a
  /// cada hijo. null si no está configurado.
  final int? ageFrom;
  final int? ageTo;

  bool get hasAgeRange => ageFrom != null && ageTo != null;

  /// "7 a 8 años"; null sin rango.
  String? get ageRangeLabel => !hasAgeRange
      ? null
      : ageFrom == ageTo
      ? '$ageFrom ${ageFrom == 1 ? 'año' : 'años'}'
      : '$ageFrom a $ageTo años';

  bool covers(int age) => hasAgeRange && age >= ageFrom! && age <= ageTo!;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: (json['categoryId'] as num?)?.toInt() ?? 0,
    name: (json['categoryName'] ?? json['name'])?.toString() ?? '',
    active: json['status'] != 'I',
    ageFrom: (json['ageFrom'] as num?)?.toInt(),
    ageTo: (json['ageTo'] as num?)?.toInt(),
  );
}

/// La categoría activa que la API asignará a un hijo de [age] años; null si
/// ninguna la cubre. Igual que en la base: ante un cruce gana la de inicio
/// mayor.
Category? categoryForAge(Iterable<Category> categories, int age) {
  final matches = [
    for (final c in categories)
      if (c.active && c.covers(age)) c,
  ]..sort((a, b) => b.ageFrom!.compareTo(a.ageFrom!));
  return matches.firstOrNull;
}

class CategoryException implements Exception {
  const CategoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Catálogo de categorías. Cualquiera con sesión lo lee; crear, editar y
/// desactivar requiere el permiso `categorias.gestionar`.
abstract class CategoryRepository {
  static CategoryRepository instance = MockCategoryRepository();

  /// Todas (activas e inactivas).
  Future<List<Category>> list();
  Future<Category> create(
    String name, {
    required int ageFrom,
    required int ageTo,
  });

  /// Solo categorías activas.
  Future<Category> update(
    int id,
    String name, {
    required int ageFrom,
    required int ageTo,
  });

  /// La API lo rechaza si algún hijo la tiene asignada.
  Future<Category> deactivate(int id);
  Future<Category> reactivate(int id);
}

class ApiCategoryRepository implements CategoryRepository {
  ApiCategoryRepository(this._api);
  final ApiClient _api;

  static const _manage = '/api/Category/ManageCategory';

  @override
  Future<List<Category>> list() async {
    final json = await _call(
      () => _api.get('/api/Category/GetCategoryData?page=1&pageSize=100'),
    );
    return (json['categoryData'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Category.fromJson)
        .toList();
  }

  @override
  Future<Category> create(
    String name, {
    required int ageFrom,
    required int ageTo,
  }) => _save('A', {
    'categoryName': name.trim(),
    'ageFrom': ageFrom,
    'ageTo': ageTo,
  });

  @override
  Future<Category> update(
    int id,
    String name, {
    required int ageFrom,
    required int ageTo,
  }) => _save('U', {
    'categoryId': id,
    'categoryName': name.trim(),
    'ageFrom': ageFrom,
    'ageTo': ageTo,
  });

  @override
  Future<Category> deactivate(int id) => _save('D', {'categoryId': id});

  @override
  Future<Category> reactivate(int id) async {
    final json = await _call(() => _api.patch('/api/Category/$id/reactivate'));
    return Category.fromJson(
      json['categoryData'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<Category> _save(String operation, Map<String, dynamic> data) async {
    final json = await _call(
      () => _api.post(_manage, {
        'typeOperation': operation,
        'categoryData': data,
      }),
    );
    return Category.fromJson(
      json['categoryData'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on ApiException catch (e) {
      throw CategoryException(e.message);
    }
  }
}

/// En memoria, para `USE_MOCK` y pruebas.
class MockCategoryRepository implements CategoryRepository {
  MockCategoryRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  final _items = <Category>[
    for (final (i, (n, from, to)) in const [
      ('Moscos', 7, 8),
      ('Preinfantil', 9, 10),
      ('Infantil', 11, 12),
      ('Intermedia', 13, 14),
      ('Juvenil', 15, 18),
    ].indexed)
      Category(id: i + 1, name: n, ageFrom: from, ageTo: to),
  ];

  @override
  Future<List<Category>> list() async {
    await Future.delayed(latency);
    return List.unmodifiable(_items);
  }

  @override
  Future<Category> create(
    String name, {
    required int ageFrom,
    required int ageTo,
  }) async {
    await Future.delayed(latency);
    _checkUnique(name);
    _checkRange(ageFrom, ageTo);
    final c = Category(
      id: _items.length + 1,
      name: name.trim(),
      ageFrom: ageFrom,
      ageTo: ageTo,
    );
    _items.add(c);
    return c;
  }

  @override
  Future<Category> update(
    int id,
    String name, {
    required int ageFrom,
    required int ageTo,
  }) async {
    await Future.delayed(latency);
    _checkUnique(name, except: id);
    _checkRange(ageFrom, ageTo, except: id);
    final i = _items.indexWhere((c) => c.id == id);
    return _items[i] = Category(
      id: id,
      name: name.trim(),
      ageFrom: ageFrom,
      ageTo: ageTo,
    );
  }

  @override
  Future<Category> deactivate(int id) => _setActive(id, false);

  @override
  Future<Category> reactivate(int id) => _setActive(id, true);

  Future<Category> _setActive(int id, bool active) async {
    await Future.delayed(latency);
    final i = _items.indexWhere((c) => c.id == id);
    final c = _items[i];
    return _items[i] = Category(
      id: id,
      name: c.name,
      active: active,
      ageFrom: c.ageFrom,
      ageTo: c.ageTo,
    );
  }

  /// Como la API: el rango no puede cruzarse con el de otra activa.
  void _checkRange(int from, int to, {int? except}) {
    for (final c in _items) {
      if (c.id == except || !c.active || !c.hasAgeRange) continue;
      if (from <= c.ageTo! && to >= c.ageFrom!) {
        throw CategoryException(
          'Ese rango se cruza con la categoría ${c.name}.',
        );
      }
    }
  }

  void _checkUnique(String name, {int? except}) {
    if (_items.any(
      (c) =>
          c.id != except && c.name.toLowerCase() == name.trim().toLowerCase(),
    )) {
      throw const CategoryException('Ya existe una categoría con ese nombre.');
    }
  }
}
