import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../app/routes.dart';
import '../data/auth_repository.dart';
import 'validators.dart';
import 'widgets/auth_field.dart';
import 'widgets/auth_header.dart';
import 'widgets/auth_switch_link.dart';
import 'widgets/loading_button.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _acceptedTerms = false;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      _showError('Debes aceptar los términos y condiciones');
      return;
    }
    setState(() => _loading = true);
    try {
      final user = await AuthRepository.instance.register(
        fullName: _name.text,
        email: _email.text,
        phone: _phone.text,
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context)
          .pushNamedAndRemoveUntil(Routes.home, (_) => false, arguments: user);
    } on AuthException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const AuthHeader(
              title: 'Crear cuenta',
              subtitle: 'Regístrate como padre, madre o tutor\npara ver a tus hijos inscritos.',
              showBack: true,
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthField(
                            label: 'Nombre completo',
                            hint: 'Ej. Carlos Pérez',
                            icon: Icons.person_outline_rounded,
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            validator: (v) =>
                                Validators.required(v, 'El nombre'),
                          ),
                          const SizedBox(height: 16),
                          AuthField(
                            label: 'Teléfono',
                            hint: 'Ej. 5555 5555',
                            icon: Icons.phone_outlined,
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            validator: Validators.phone,
                          ),
                          const SizedBox(height: 16),
                          AuthField(
                            label: 'Correo electrónico',
                            hint: 'tucorreo@ejemplo.com',
                            icon: Icons.mail_outline_rounded,
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            validator: Validators.email,
                          ),
                          const SizedBox(height: 16),
                          AuthField(
                            label: 'Contraseña',
                            hint: 'Mínimo 6 caracteres',
                            icon: Icons.lock_outline_rounded,
                            controller: _password,
                            isPassword: true,
                            autofillHints: const [AutofillHints.newPassword],
                            validator: Validators.password,
                          ),
                          const SizedBox(height: 16),
                          AuthField(
                            label: 'Confirmar contraseña',
                            hint: 'Repite tu contraseña',
                            icon: Icons.lock_outline_rounded,
                            controller: _confirm,
                            isPassword: true,
                            textInputAction: TextInputAction.done,
                            validator: (v) => v != _password.text
                                ? 'Las contraseñas no coinciden'
                                : null,
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: _acceptedTerms,
                            onChanged: (v) =>
                                setState(() => _acceptedTerms = v ?? false),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                            title: const Text(
                              'Acepto los términos y condiciones y el uso de mis datos por el club.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          LoadingButton(
                            label: 'Crear cuenta',
                            loading: _loading,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 12),
                          AuthSwitchLink(
                            question: '¿Ya tienes cuenta?',
                            action: 'Inicia sesión',
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
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
