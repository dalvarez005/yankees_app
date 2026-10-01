import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/auth/presentation/widgets/auth_field.dart';

/// "1,250.5" → 1250.5; null si no es un número.
double? parseMoney(String? text) =>
    double.tryParse((text ?? '').trim().replaceAll(',', ''));

/// Texto inicial de un campo de monto: "150" o "150.50".
/// Error de un monto escrito, o null si es válido. Es el validador de
/// [MoneyField]; también sirve para saber si un formulario está completo.
String? moneyError(String? v, {bool allowZero = false}) {
  if ((v ?? '').trim().isEmpty) return 'Escribe el monto';
  final amount = parseMoney(v);
  if (amount == null) return 'Monto inválido';
  if (allowZero ? amount < 0 : amount <= 0) {
    return allowZero ? 'No puede ser negativo' : 'Debe ser mayor a 0';
  }
  if (amount > 100000) return 'Máximo Q 100,000';
  if (RegExp(r'\.\d{3,}$').hasMatch(v!.trim())) return 'Máximo 2 decimales';
  return null;
}

String moneyText(double? amount) {
  if (amount == null) return '';
  return amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
}

/// Monto en quetzales con hasta 2 decimales. Por defecto exige que sea
/// mayor a 0 y hasta Q 100,000 (límite de la API); con [allowZero] acepta 0.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = 'Ej. 150.00',
    this.allowZero = false,
    this.extraValidator,
    this.enabled = true,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool allowZero;
  final bool enabled;

  /// Validación adicional con el monto ya interpretado.
  final String? Function(double amount)? extraValidator;

  @override
  Widget build(BuildContext context) => AuthField(
    label: label,
    hint: hint,
    icon: Icons.payments_outlined,
    controller: controller,
    enabled: enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
      LengthLimitingTextInputFormatter(12),
    ],
    validator: (v) =>
        moneyError(v, allowZero: allowZero) ??
        extraValidator?.call(parseMoney(v)!),
  );
}
