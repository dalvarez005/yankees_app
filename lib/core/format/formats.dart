/// Formatos en español (Guatemala) sin depender de `intl`.
library;

/// "Q 1,250.00"
String formatMoney(num amount) {
  final negative = amount < 0;
  final cents = (amount.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  final decimals = (cents % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}Q $buffer.$decimals';
}

const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// "29 sep 2026"
String formatDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// "29 sep 2026, 14:05"
String formatDateTime(DateTime date) {
  final d = date.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${formatDate(d)}, $hh:$mm';
}

/// Días desde hoy hasta [date] (negativo si ya pasó), por fecha calendario.
int daysUntil(DateTime date, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  return _dateOnly(date.toLocal()).difference(today).inDays;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
