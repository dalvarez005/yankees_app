import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_ready.dart';
import '../data/auth_repository.dart';
import 'validators.dart';
import 'widgets/auth_field.dart';
import 'widgets/auth_header.dart';
import 'widgets/loading_button.dart';

/// Recuperar contraseña en dos pasos: se pide el correo y se envía un
/// código; con el código se define la contraseña nueva.
///
/// Al terminar vuelve con `true` para que el inicio de sesión avise.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> with FormReady {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// Ya se pidió el código: se muestran código y contraseña nueva.
  bool _codeSent = false;
  bool _loading = false;

  static String? _codeError(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Escribe el código';
    if (value.length != 6) return 'El código tiene 6 dígitos';
    return null;
  }

  bool get _ready => !_codeSent
      ? Validators.email(_email.text) == null
      : _codeError(_code.text) == null &&
            Validators.password(_password.text) == null &&
            Validators.confirmPassword(_confirm.text, _password.text) == null;

  @override
  void initState() {
    super.initState();
    watchFields([_email, _code, _password, _confirm]);
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
    await AuthRepository.instance.sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() => _codeSent = true);
    showAppMessage(
      context,
      'Si el correo está registrado, te llegará un código en un momento.',
      info: true,
    );
  });

  Future<void> _changePassword() => _run(() async {
    if (!_formKey.currentState!.validate()) return;
    await AuthRepository.instance.resetPassword(
      email: _email.text,
      code: _code.text,
      newPassword: _password.text,
    );
    if (mounted) Navigator.of(context).pop(true);
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            AuthHeader(
              title: 'Recuperar contraseña',
              subtitle: _codeSent
                  ? 'Escribe el código que enviamos a\n${_email.text.trim()}'
                  : 'Te enviaremos un código a tu correo\npara que definas una nueva.',
              showBack: true,
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _codeSent
                          ? [
                              AuthField(
                                label: 'Código',
                                hint: '6 dígitos',
                                icon: Icons.pin_outlined,
                                controller: _code,
                                keyboardType: TextInputType.number,
                                autofillHints: const [
                                  AutofillHints.oneTimeCode,
                                ],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                validator: _codeError,
                              ),
                              const SizedBox(height: 18),
                              AuthField(
                                label: 'Contraseña nueva',
                                hint: 'Mínimo 6 caracteres',
                                icon: Icons.lock_outline_rounded,
                                controller: _password,
                                isPassword: true,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                validator: Validators.password,
                              ),
                              const SizedBox(height: 18),
                              AuthField(
                                label: 'Confirmar contraseña',
                                hint: 'Repite la contraseña nueva',
                                icon: Icons.lock_outline_rounded,
                                controller: _confirm,
                                isPassword: true,
                                textInputAction: TextInputAction.done,
                                validator: (v) => Validators.confirmPassword(
                                  v,
                                  _password.text,
                                ),
                                onSubmitted: (_) {
                                  if (_ready) _changePassword();
                                },
                              ),
                              const SizedBox(height: 24),
                              LoadingButton(
                                label: 'Cambiar contraseña',
                                loading: _loading,
                                onPressed: _ready ? _changePassword : null,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'El código vence en 15 minutos. Si no llega, '
                                'revisa la carpeta de spam.',
                                textAlign: TextAlign.center,
                                style: text.bodySmall,
                              ),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => setState(() {
                                        _codeSent = false;
                                        _code.clear();
                                      }),
                                child: const Text('Pedir otro código'),
                              ),
                            ]
                          : [
                              AuthField(
                                label: 'Correo electrónico',
                                hint: 'tucorreo@ejemplo.com',
                                icon: Icons.mail_outline_rounded,
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.email],
                                validator: Validators.email,
                                onSubmitted: (_) {
                                  if (_ready) _sendCode();
                                },
                              ),
                              const SizedBox(height: 24),
                              LoadingButton(
                                label: 'Enviar código',
                                loading: _loading,
                                onPressed: _ready ? _sendCode : null,
                              ),
                            ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
