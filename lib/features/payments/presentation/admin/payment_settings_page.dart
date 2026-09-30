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
import '../../data/payment_models.dart';
import '../../data/payments_repository.dart';

/// Número de WhatsApp al que escriben los padres cuando les rechazan un
/// comprobante (requiere `configuracion.gestionar`).
class PaymentSettingsPage extends StatefulWidget {
  const PaymentSettingsPage({super.key, required this.user});

  final AppUser user;

  @override
  State<PaymentSettingsPage> createState() => _PaymentSettingsPageState();
}

class _PaymentSettingsPageState extends State<PaymentSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _country = TextEditingController(text: '502');
  final _number = TextEditingController();
  final _name = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _country.dispose();
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await PaymentsRepository.instance.contact();
      if (!mounted) return;
      // Guatemala por defecto: 502 + 8 dígitos.
      final digits = c.whatsappNumber;
      if (digits.length > 8) {
        _country.text = digits.substring(0, digits.length - 8);
        _number.text = digits.substring(digits.length - 8);
      } else {
        _number.text = digits;
      }
      _name.text = c.displayName ?? '';
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

  String get _full => '${_country.text.trim()}${_number.text.trim()}';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await PaymentsRepository.instance.updateContact(
        PaymentContact(
          whatsappNumber: _full,
          displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        ),
      );
      if (mounted) showAppMessage(context, 'Contacto guardado.');
    } on PaymentsException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
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
      appBar: pageAppBar(context, 'Contacto de pagos'),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.navy),
            )
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
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
                        Icon(Icons.chat_rounded, color: Color(0xFF128C7E)),
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
                              (v ?? '').isEmpty ? 'Requerido' : null,
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
                          validator: (v) =>
                              (v ?? '').length < 8 ? 'Mínimo 8 dígitos' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AuthField(
                    label: 'Nombre a mostrar (opcional)',
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
                    onPressed: _save,
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _test,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Probar el chat'),
                  ),
                ],
              ),
            ),
    );
  }
}
