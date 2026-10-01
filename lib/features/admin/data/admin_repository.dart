import '../../../core/network/api_client.dart';

class AdminException implements Exception {
  const AdminException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PermissionInfo {
  const PermissionInfo({
    required this.code,
    required this.name,
    required this.module,
    this.description,
  });

  final String code;
  final String name;
  final String? description;
  final String module;

  factory PermissionInfo.fromJson(Map<String, dynamic> j) => PermissionInfo(
    code: j['code']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    description: j['description']?.toString(),
    module: j['module']?.toString() ?? '',
  );
}

class Role {
  const Role({
    required this.id,
    required this.name,
    required this.permissions,
    this.active = true,
    this.userCount = 0,
  });

  final int id;
  final String name;
  final bool active;
  final Set<String> permissions;
  final int userCount;

  /// SUPER_ADMIN siempre tiene todos los permisos: no se editan.
  bool get isSuperAdmin => name.trim().toUpperCase() == 'SUPER_ADMIN';

  /// Rol que el registro asigna a los usuarios nuevos.
  bool get isDefault => id == 1;

  /// La API no permite renombrar ni desactivar estos roles.
  bool get isSystem => isDefault || isSuperAdmin;

  factory Role.fromJson(Map<String, dynamic> j) => Role(
    id: (j['roleId'] as num?)?.toInt() ?? 0,
    name: j['roleName']?.toString() ?? '',
    active: j['status'] != 'I',
    permissions: {...?(j['permissions'] as List?)?.map((p) => p.toString())},
    userCount: (j['userCount'] as num?)?.toInt() ?? 0,
  );
}

class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.email,
    required this.name,
    required this.active,
    this.roleId,
    this.roleName,
    this.googleLinked = false,
  });

  final String id;
  final String email;
  final String name;
  final int? roleId;
  final String? roleName;
  final bool active;
  final bool googleLinked;

  factory ManagedUser.fromJson(Map<String, dynamic> j) => ManagedUser(
    id: j['userId']?.toString() ?? '',
    email: j['email']?.toString() ?? '',
    name: [
      j['firstName'],
      j['firstLastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' '),
    roleId: (j['roleId'] as num?)?.toInt(),
    roleName: j['roleName']?.toString(),
    active: j['status'] == 'A',
    googleLinked: j['googleLinked'] == true,
  );
}

/// Jugador (hijo inscrito) en el listado general del club.
class Player {
  const Player({
    required this.name,
    required this.lastName,
    this.dependentId,
    this.cui,
    this.age,
    this.categoryId,
    this.categoryName,
    this.parentUserId,
    this.parentName,
    this.parentSolvent,
  });

  final String? dependentId;
  final String name;
  final String lastName;
  final String? cui;
  final int? age;
  final int? categoryId;
  final String? categoryName;
  final String? parentUserId;
  final String? parentName;

  /// null si el padre está exento o pendiente de validación.
  final bool? parentSolvent;

  String get fullName => [name, lastName].where((p) => p.isNotEmpty).join(' ');

  factory Player.fromJson(Map<String, dynamic> j) => Player(
    name: j['name']?.toString().trim() ?? '',
    lastName: j['lastName']?.toString().trim() ?? '',
    cui: j['cui']?.toString(),
    age: (j['age'] as num?)?.toInt(),
    categoryId: (j['categoryId'] as num?)?.toInt(),
    categoryName: j['categoryName']?.toString(),
    dependentId: j['dependentId']?.toString(),
    parentUserId: j['parentUserId']?.toString(),
    parentName: j['parentName']?.toString(),
    parentSolvent: j['parentSolvent'] is bool
        ? j['parentSolvent'] as bool
        : null,
  );
}

/// Roles, permisos y usuarios. Cada operación exige su permiso en la API
/// (la app además oculta lo que el usuario no puede hacer).
abstract class AdminRepository {
  static AdminRepository instance = UnavailableAdminRepository();

  Future<List<PermissionInfo>> permissions();

  /// Roles activos con sus permisos.
  Future<List<Role>> roles();
  Future<Role> createRole({
    required String name,
    required Set<String> permissions,
  });
  Future<void> updateRole(int id, {String? name, Set<String>? permissions});

  /// La API lo desactiva (no se borra); falla si tiene usuarios.
  Future<void> deleteRole(int id);
  Future<List<ManagedUser>> users({String? search});
  Future<void> setUserRole(String userId, int roleId);
  Future<ManagedUser> setUserActive(String userId, bool active);

  /// Hijos inscritos con su categoría y su padre (`jugadores.ver`),
  /// filtrados en la API por categoría y nombre o CUI.
  /// Con [page] trae solo esa página; sin él, todas.
  Future<List<Player>> players({
    int? categoryId,
    String? search,
    int? page,
    int pageSize = 100,
  });
}

class ApiAdminRepository implements AdminRepository {
  ApiAdminRepository(this._api);
  final ApiClient _api;

  static const _manageRole = '/api/Role/ManageRole';
  static const _rolePermissions = '/api/Role/UpdateRolePermissions';

  @override
  Future<List<PermissionInfo>> permissions() async {
    final json = await _call(
      () => _api.get('/api/Permission/GetPermissionData'),
    );
    return _list(json['permissionData'], PermissionInfo.fromJson);
  }

  @override
  Future<List<Role>> roles() async {
    final json = await _call(() => _api.get('/api/Role/GetRolePermissions'));
    return _list(
      json['roleData'],
      Role.fromJson,
    ).where((r) => r.active).toList();
  }

  /// El rol se crea con su nombre y luego se le asignan los permisos.
  @override
  Future<Role> createRole({
    required String name,
    required Set<String> permissions,
  }) async {
    final json = await _call(
      () => _api.post(_manageRole, {
        'typeOperation': 'A',
        'roleData': {'roleName': name.trim()},
      }),
    );
    final created = Role.fromJson(
      json['roleData'] as Map<String, dynamic>? ?? const {},
    );
    if (permissions.isEmpty) return created;
    return _setPermissions(created.id, permissions);
  }

  @override
  Future<void> updateRole(
    int id, {
    String? name,
    Set<String>? permissions,
  }) async {
    if (name != null) {
      await _call(
        () => _api.post(_manageRole, {
          'typeOperation': 'U',
          'roleData': {'roleId': id, 'roleName': name.trim()},
        }),
      );
    }
    if (permissions != null) await _setPermissions(id, permissions);
  }

  @override
  Future<void> deleteRole(int id) async {
    await _call(
      () => _api.post(_manageRole, {
        'typeOperation': 'D',
        'roleData': {'roleId': id},
      }),
    );
  }

  @override
  Future<List<ManagedUser>> users({String? search}) async {
    final q = search?.trim() ?? '';
    final path = q.isEmpty
        ? '/api/User/GetUserData'
        : '/api/User/GetUserData?search=${Uri.encodeQueryComponent(q)}';
    final json = await _call(() => _api.get(path));
    return _list(json['userData'], ManagedUser.fromJson);
  }

  @override
  Future<void> setUserRole(String userId, int roleId) async {
    await _call(
      () => _api.post('/api/User/UpdateUserRole', {
        'userId': userId,
        'roleId': roleId,
      }),
    );
  }

  @override
  Future<ManagedUser> setUserActive(String userId, bool active) async {
    final json = await _call(
      () => _api.post('/api/User/UpdateUserStatus', {
        'userId': userId,
        'status': active ? 'A' : 'I',
      }),
    );
    return ManagedUser.fromJson(
      json['userData'] as Map<String, dynamic>? ?? const {},
    );
  }

  @override
  Future<List<Player>> players({
    int? categoryId,
    String? search,
    int? page,
    int pageSize = 100,
  }) async {
    final all = <Player>[];
    final q = search?.trim() ?? '';
    for (var p = page ?? 1; p <= (page ?? 20); p++) {
      final path = Uri(
        path: '/api/Dependent/GetDependentDataByCategory',
        queryParameters: {
          'categoryId': ?categoryId?.toString(),
          if (q.isNotEmpty) 'search': q,
          'page': '$p',
          'pageSize': '$pageSize',
        },
      );
      final json = await _call(() => _api.get(path.toString()));
      all.addAll(_list(json['dependentData'], Player.fromJson));
      if (json['hasNext'] != true) break;
    }
    return all;
  }

  Future<Role> _setPermissions(int roleId, Set<String> permissions) async {
    final json = await _call(
      () => _api.post(_rolePermissions, {
        'roleId': roleId,
        'permissions': permissions.toList(),
      }),
    );
    return Role.fromJson(json['roleData'] as Map<String, dynamic>? ?? const {});
  }

  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) => (raw as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(fromJson)
      .toList();

  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on ApiException catch (e) {
      throw AdminException(e.message);
    }
  }
}

/// Sin API (modo mock): el panel de admin avisa que no está disponible.
class UnavailableAdminRepository implements AdminRepository {
  static const _msg = 'La administración requiere conexión con la API.';
  Never _fail() => throw const AdminException(_msg);

  @override
  Future<List<PermissionInfo>> permissions() async => _fail();
  @override
  Future<List<Role>> roles() async => _fail();
  @override
  Future<Role> createRole({
    required String name,
    required Set<String> permissions,
  }) async => _fail();
  @override
  Future<void> updateRole(
    int id, {
    String? name,
    Set<String>? permissions,
  }) async => _fail();
  @override
  Future<void> deleteRole(int id) async => _fail();
  @override
  Future<List<ManagedUser>> users({String? search}) async => _fail();
  @override
  Future<void> setUserRole(String userId, int roleId) async => _fail();
  @override
  Future<ManagedUser> setUserActive(String userId, bool active) async =>
      _fail();
  @override
  Future<List<Player>> players({
    int? categoryId,
    String? search,
    int? page,
    int pageSize = 100,
  }) async => _fail();
}
