import 'package:flutter/material.dart';

import '../data/app_user.dart';
import '../data/auth_repository.dart';
import '../../profile/presentation/enter_app.dart';
import 'validators.dart';
import 'widgets/auth_field.dart';
import 'widgets/auth_header.dart';
import 'widgets/auth_switch_link.dart';
import 'widgets/google_button.dart';
import 'widgets/loading_button.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_ready.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> with FormReady {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _firstName = TextEditingController();
  final _firstLastName = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;

  bool get _ready =>
      Validators.name(_firstName.text, 'El nombre') == null &&
      Validators.name(_firstLastName.text, 'El apellido') == null &&
      Validators.email(_email.text) == null &&
      Validators.password(_password.text) == null &&
      Validators.confirmPassword(_confirm.text, _password.text) == null;

  @override
  void initState() {
    super.initState();
    watchFields([_email, _firstName, _firstLastName, _password, _confirm]);
  }

  @override
  void dispose() {
    for (final c in [_email, _firstName, _firstLastName, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final user = await AuthRepository.instance.register(
        email: _email.text,
        firstName: _firstName.text,
        firstLastName: _firstLastName.text,
        password: _password.text,
      );
      _goHome(user);
    } on AuthException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    setState(() => _googleLoading = true);
    try {
      final user = await AuthRepository.instance.signInWithGoogle();
      if (user != null) _goHome(user);
    } on AuthException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _goHome(AppUser user) {
    if (!mounted) return;
    enterApp(context, user);
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppMessage(context, message, error: true);
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
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GoogleButton(
                            loading: _googleLoading,
                            onPressed: _loading ? null : _google,
                          ),
                          const OrDivider(),
                          AuthField(
                            label: 'Nombre',
                            hint: 'Ej. Carlos',
                            icon: Icons.badge_outlined,
                            controller: _firstName,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.givenName],
                            validator: (v) => Validators.name(v, 'El nombre'),
                          ),
                          const SizedBox(height: 16),
                          AuthField(
                            label: 'Primer apellido',
                            hint: 'Ej. Pérez',
                            icon: Icons.badge_outlined,
                            controller: _firstLastName,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.familyName],
                            validator: (v) => Validators.name(v, 'El apellido'),
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
                            validator: (v) =>
                                Validators.confirmPassword(v, _password.text),
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 24),
                          LoadingButton(
                            label: 'Crear cuenta',
                            loading: _loading,
                            onPressed: _googleLoading || !_ready
                                ? null
                                : _submit,
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
