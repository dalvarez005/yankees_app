import 'package:flutter/material.dart';

import '../../../app/routes.dart';
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

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with FormReady {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;

  bool get _busy => _loading || _googleLoading;

  bool get _ready =>
      Validators.email(_email.text) == null &&
      Validators.password(_password.text) == null;

  @override
  void initState() {
    super.initState();
    watchFields([_email, _password]);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final user = await AuthRepository.instance.signIn(
        email: _email.text,
        password: _password.text,
      );
      _goHome(user);
    } on AuthException catch (e) {
      _showMessage(e.message, error: true);
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
      _showMessage(e.message, error: true);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _goHome(AppUser user) {
    if (!mounted) return;
    enterApp(context, user);
  }

  Future<void> _forgotPassword() async {
    if (Validators.email(_email.text) != null) {
      _showMessage(
        'Escribe tu correo arriba para recuperar tu contraseña',
        info: true,
      );
      return;
    }
    await AuthRepository.instance.sendPasswordReset(_email.text);
    _showMessage('Te enviamos un enlace a ${_email.text.trim()}');
  }

  void _showMessage(String message, {bool error = false, bool info = false}) {
    if (!mounted) return;
    showAppMessage(context, message, error: error, info: info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const AuthHeader(
              title: 'Bienvenido',
              subtitle: 'Consulta pagos, inscripciones y comprobantes\nde tus hijos en un solo lugar.',
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
                          AuthField(
                            label: 'Correo electrónico',
                            hint: 'tucorreo@ejemplo.com',
                            icon: Icons.mail_outline_rounded,
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            validator: Validators.email,
                          ),
                          const SizedBox(height: 18),
                          AuthField(
                            label: 'Contraseña',
                            hint: '••••••••',
                            icon: Icons.lock_outline_rounded,
                            controller: _password,
                            isPassword: true,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            validator: Validators.password,
                            onSubmitted: (_) => _submit(),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _forgotPassword,
                              child: const Text('¿Olvidaste tu contraseña?'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          LoadingButton(
                            label: 'Ingresar',
                            loading: _loading,
                            onPressed: _googleLoading || !_ready
                                ? null
                                : _submit,
                          ),
                          const OrDivider(),
                          GoogleButton(
                            loading: _googleLoading,
                            onPressed: _loading ? null : _google,
                          ),
                          const SizedBox(height: 12),
                          AuthSwitchLink(
                            question: '¿No tienes cuenta?',
                            action: 'Regístrate',
                            onTap: () =>
                                Navigator.of(context)
                                    .pushNamed(Routes.register),
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
