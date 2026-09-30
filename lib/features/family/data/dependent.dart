/// Hijo/a (dependiente) registrado por el padre, madre o tutor.
class Dependent {
  const Dependent({
    required this.id,
    required this.cui,
    required this.firstName,
    required this.firstLastName,
    required this.categoryId,
    this.categoryName,
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

  /// Nombre que manda la API al listar (en la lista no viene el id).
  final String? categoryName;

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

  Dependent withCategoryId(int id) => Dependent(
    id: this.id,
    cui: cui,
    firstName: firstName,
    secondName: secondName,
    firstLastName: firstLastName,
    secondLastName: secondLastName,
    categoryId: id,
    categoryName: categoryName,
  );

  factory Dependent.fromJson(Map<String, dynamic> json) => Dependent(
    id: json['dependentId']?.toString() ?? '',
    cui: json['cui']?.toString() ?? '',
    firstName: json['firstName']?.toString() ?? '',
    secondName: _blankToNull(json['secondName']),
    firstLastName: json['firstLastName']?.toString() ?? '',
    secondLastName: _blankToNull(json['secondLastName']),
    categoryId: (json['categoryId'] as num?)?.toInt() ?? 0,
    categoryName: _blankToNull(json['categoryName']),
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
