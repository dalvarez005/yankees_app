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
    this.age,
    this.birthDate,
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

  /// Años, calculados por la API a partir de [birthDate].
  final int? age;

  /// Fecha de nacimiento; null en registros anteriores a que la API la pidiera.
  final DateTime? birthDate;

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
    age: age,
    birthDate: birthDate,
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
    age: (json['age'] as num?)?.toInt(),
    birthDate: DateTime.tryParse(json['birthDate']?.toString() ?? ''),
  );

  static String? _blankToNull(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}

/// Datos que se envían al crear o editar. La edad y la categoría no se
/// envían: la API las calcula con la fecha de nacimiento.
class DependentInput {
  const DependentInput({
    required this.cui,
    required this.firstName,
    required this.firstLastName,
    required this.birthDate,
    this.secondName,
    this.secondLastName,
  });

  final String cui;
  final String firstName;
  final String? secondName;
  final String firstLastName;
  final String? secondLastName;
  final DateTime birthDate;

  Map<String, dynamic> toJson() => {
    'cui': cui,
    'firstName': firstName,
    if (secondName != null && secondName!.isNotEmpty) 'secondName': secondName,
    'firstLastName': firstLastName,
    if (secondLastName != null && secondLastName!.isNotEmpty)
      'secondLastName': secondLastName,
    'dateBirthday': isoDate(birthDate),
  };
}

/// "2017-03-09": la fecha sin hora ni zona, como la espera la API.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Años cumplidos a [today].
int ageAt(DateTime birthDate, DateTime today) {
  var age = today.year - birthDate.year;
  if (today.month < birthDate.month ||
      (today.month == birthDate.month && today.day < birthDate.day)) {
    age--;
  }
  return age;
}
