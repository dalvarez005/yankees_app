import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_colors.dart';
import '../../../../core/access/permissions.dart';
import '../../../../core/contact/whatsapp.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../auth/data/app_user.dart';
import '../../../auth/presentation/widgets/auth_field.dart';
import '../../../auth/presentation/widgets/loading_button.dart';
import '../../../../core/widgets/money_field.dart';
import '../../data/payment_models.dart';
import '../../data/payments_repository.dart';
import '../../data/settings_repository.dart';
import '../../../../core/widgets/form_ready.dart';
import '../../../../core/widgets/whatsapp_logo.dart';

/// Configuración de pagos (requiere `configuracion.gestionar`): cuotas
/// sugeridas al validar usuarios, día límite de pago y el WhatsApp al que
/// escriben los padres.
class PaymentSettingsPage extends StatefulWidget {
  const PaymentSettingsPage({super.key, required this.user});

  final AppUser user;

  @override
  State<PaymentSettingsPage> createState() => _PaymentSettingsPageState();
}

class _PaymentSettingsPageState extends State<PaymentSettingsPage>
    with FormReady {
  final _formKey = GlobalKey<FormState>();
  final _country = TextEditingController(text: '502');
  final _number = TextEditingController();
  final _name = TextEditingController();
  final _enrollment = TextEditingController();
  final _monthly = TextEditingController();
  int _dueDay = 15;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? _numberError(String? v) {
    final n = v ?? '';
    if (n.isEmpty) return null; // Sin contacto.
    if (n.length < 8) return 'Mínimo 8 dígitos';
    if (_full.length > 15) return 'Máximo 15 en total';
    return null;
  }

  bool get _ready =>
      moneyError(_enrollment.text, allowZero: true) == null &&
      moneyError(_monthly.text, allowZero: true) == null &&
      _numberError(_number.text) == null &&
      !(_number.text.trim().isNotEmpty && _country.text.trim().isEmpty) &&
      _name.text.length <= 60;

  @override
  void initState() {
    super.initState();
    watchFields([_country, _number, _name, _enrollment, _monthly]);
    _load();
  }

  @override
  void dispose() {
    _country.dispose();
    _number.dispose();
    _name.dispose();
    _enrollment.dispose();
    _monthly.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await SettingsRepository.instance.paymentSettings();
      if (!mounted) return;
      _enrollment.text = moneyText(c.defaultEnrollmentFee);
      _monthly.text = moneyText(c.defaultMonthlyFee);
      _dueDay = c.dueDay.clamp(1, 28);
      // Guatemala por defecto: 502 + 8 dígitos.
      final digits = c.whatsappNumber;
      if (digits.length > 8) {
        _country.text = digits.substring(0, digits.length - 8);
        _number.text = digits.substring(digits.length - 8);
      } else {
        _number.text = digits;
      }
      _name.text = c.contactName ?? '';
      setState(() => _loading = false);
    } on PaymentsException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  /// Vacío si no se escribió número (se permite: sin contacto).
  String get _full => _number.text.trim().isEmpty
      ? ''
      : '${_country.text.trim()}${_number.text.trim()}';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SettingsRepository.instance.updatePaymentSettings(
        PaymentSettings(
          defaultEnrollmentFee: parseMoney(_enrollment.text) ?? 0,
          defaultMonthlyFee: parseMoney(_monthly.text) ?? 0,
          dueDay: _dueDay,
          whatsappNumber: _full,
          contactName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        ),
      );
      if (mounted) showAppMessage(context, 'Configuración guardada.');
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    if (_full.isEmpty) {
      showAppMessage(context, 'Escribe primero el número.', info: true);
      return;
    }
    final ok = await openWhatsApp(
      _full,
      message: 'Prueba de contacto desde la app del Club Yankees.',
    );
    if (!ok && mounted) {
      showAppMessage(context, 'No se pudo abrir WhatsApp.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.settingsManage)) {
      return const NoAccessView();
    }
    return Scaffold(
      appBar: pageAppBar(context, 'Configuración de pagos'),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.navy),
            )
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  const ListHeader('Cuotas sugeridas'),
                  const Text(
                    'Se proponen al validar a un usuario nuevo; se pueden '
                    'cambiar para cada familia.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  MoneyField(
                    label: 'Inscripción',
                    controller: _enrollment,
                    allowZero: true,
                  ),
                  const SizedBox(height: 16),
                  MoneyField(
                    label: 'Mensualidad',
                    controller: _monthly,
                    allowZero: true,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _dueDay,
                    decoration: const InputDecoration(
                      labelText: 'Día límite de pago',
                      prefixIcon: Icon(Icons.event_rounded, size: 20),
                    ),
                    items: [
                      for (var d = 1; d <= 28; d++)
                        DropdownMenuItem(value: d, child: Text('Día $d')),
                    ],
                    onChanged: (v) => setState(() => _dueDay = v ?? _dueDay),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'La mensualidad vence el día $_dueDay de cada mes y la '
                    'inscripción $_dueDay días después de validar al usuario.',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const ListHeader('Contacto por WhatsApp'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF25D366).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        WhatsAppLogo(size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Cuando se rechaza un comprobante, el padre ve un '
                            'botón que abre WhatsApp con este número y un '
                            'mensaje con el detalle del cobro.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 104,
                        child: AuthField(
                          label: 'País',
                          hint: '502',
                          icon: Icons.add_rounded,
                          controller: _country,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          validator: (v) =>
                              _number.text.trim().isNotEmpty &&
                                  (v ?? '').isEmpty
                              ? 'Requerido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AuthField(
                          label: 'Número de WhatsApp',
                          hint: '5555 1234',
                          icon: Icons.phone_iphone_rounded,
                          controller: _number,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(12),
                          ],
                          validator: _numberError,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AuthField(
                    label: 'Nombre del contacto',
                    hint: 'Ej. Tesorería del club',
                    icon: Icons.badge_outlined,
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        (v?.length ?? 0) > 60 ? 'Máximo 60 caracteres' : null,
                  ),
                  const SizedBox(height: 28),
                  LoadingButton(
                    label: 'Guardar',
                    loading: _saving,
                    onPressed: _ready ? _save : null,
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    // Sin número no hay chat que probar.
                    onPressed: _ready && _number.text.trim().isNotEmpty
                        ? _test
                        : null,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Probar el chat'),
                  ),
                ],
              ),
            ),
    );
  }
}
