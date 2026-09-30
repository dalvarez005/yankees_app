import '../../../core/network/api_client.dart';

class Category {
  const Category({required this.id, required this.name, this.active = true});

  final int id;
  final String name;

  /// Inactiva: no se ofrece para hijos nuevos, pero se conserva en los que
  /// ya la tienen.
  final bool active;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: (json['categoryId'] as num?)?.toInt() ?? 0,
    name: (json['categoryName'] ?? json['name'])?.toString() ?? '',
    active: json['status'] != 'I',
  );
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
  Future<Category> create(String name);

  /// Solo categorías activas.
  Future<Category> rename(int id, String name);

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
  Future<Category> create(String name) =>
      _save('A', {'categoryName': name.trim()});

  @override
  Future<Category> rename(int id, String name) =>
      _save('U', {'categoryId': id, 'categoryName': name.trim()});

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
    for (final (i, n) in const [
      'Moscos',
      'Preinfantil',
      'Infantil',
      'Intermedia',
      'Juvenil',
    ].indexed)
      Category(id: i + 1, name: n),
  ];

  @override
  Future<List<Category>> list() async {
    await Future.delayed(latency);
    return List.unmodifiable(_items);
  }

  @override
  Future<Category> create(String name) async {
    await Future.delayed(latency);
    _checkUnique(name);
    final c = Category(id: _items.length + 1, name: name.trim());
    _items.add(c);
    return c;
  }

  @override
  Future<Category> rename(int id, String name) async {
    await Future.delayed(latency);
    _checkUnique(name, except: id);
    final i = _items.indexWhere((c) => c.id == id);
    return _items[i] = Category(id: id, name: name.trim());
  }

  @override
  Future<Category> deactivate(int id) async {
    await Future.delayed(latency);
    final i = _items.indexWhere((c) => c.id == id);
    return _items[i] = Category(id: id, name: _items[i].name, active: false);
  }

  @override
  Future<Category> reactivate(int id) async {
    await Future.delayed(latency);
    final i = _items.indexWhere((c) => c.id == id);
    return _items[i] = Category(id: id, name: _items[i].name);
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
