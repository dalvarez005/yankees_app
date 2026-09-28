/// Hijo/a (dependiente) registrado por el padre, madre o tutor.
class Dependent {
  const Dependent({
    required this.id,
    required this.cui,
    required this.firstName,
    required this.firstLastName,
    required this.categoryId,
    this.secondName,
    this.secondLastName,
  });

  final String id;

  /// CUI del DPI / certificado de nacimiento (13 dígitos).
  final String cui;
  final String firstName;
  final String? secondName;
  final String firstLastName;
  final String? secondLastName;
  final int categoryId;

  String get fullName => [
    firstName,
    secondName,
    firstLastName,
    secondLastName,
  ].where((p) => p != null && p.trim().isNotEmpty).join(' ');

  String get initials =>
      '${firstName.isEmpty ? '' : firstName[0]}'
              '${firstLastName.isEmpty ? '' : firstLastName[0]}'
          .toUpperCase();

  /// "1234 56789 0101", como aparece en el DPI.
  String get formattedCui => cui.length == 13
      ? '${cui.substring(0, 4)} ${cui.substring(4, 9)} ${cui.substring(9)}'
      : cui;

  factory Dependent.fromJson(Map<String, dynamic> json) => Dependent(
    id: json['dependentId']?.toString() ?? '',
    cui: json['cui']?.toString() ?? '',
    firstName: json['firstName']?.toString() ?? '',
    secondName: _blankToNull(json['secondName']),
    firstLastName: json['firstLastName']?.toString() ?? '',
    secondLastName: _blankToNull(json['secondLastName']),
    categoryId: (json['categoryId'] as num?)?.toInt() ?? 0,
  );

  static String? _blankToNull(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}

/// Datos que se envían al crear o editar.
class DependentInput {
  const DependentInput({
    required this.cui,
    required this.firstName,
    required this.firstLastName,
    required this.categoryId,
    this.secondName,
    this.secondLastName,
  });

  final String cui;
  final String firstName;
  final String? secondName;
  final String firstLastName;
  final String? secondLastName;
  final int categoryId;

  Map<String, dynamic> toJson() => {
    'cui': cui,
    'firstName': firstName,
    if (secondName != null && secondName!.isNotEmpty) 'secondName': secondName,
    'firstLastName': firstLastName,
    if (secondLastName != null && secondLastName!.isNotEmpty)
      'secondLastName': secondLastName,
    'categoryId': categoryId,
  };
}

class Category {
  const Category(this.id, this.name);
  final int id;
  final String name;
}

/// TEMPORAL: la tabla category_catalog de la API está vacía y no hay
/// endpoint para listarla. Cuando exista, reemplazar por lo que devuelva
/// la API (los ids deben coincidir con los de la base).
const categories = [
  Category(1, 'Sub-8'),
  Category(2, 'Sub-10'),
  Category(3, 'Sub-12'),
  Category(4, 'Sub-14'),
  Category(5, 'Sub-16'),
];

String categoryName(int id) => categories
    .firstWhere((c) => c.id == id, orElse: () => Category(id, 'Categoría $id'))
    .name;
