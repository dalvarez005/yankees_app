import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../data/app_user.dart';
import '../data/auth_repository.dart';
import '../../profile/presentation/enter_app.dart';
import 'reset_password_page.dart';
import 'validators.dart';
import 'widgets/auth_field.dart';
import 'widgets/auth_header.dart';
import 'widgets/auth_switch_link.dart';
import 'widgets/google_button.dart';
import 'widgets/google_sign_in_area.dart';
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

  /// Web: el botón de Google ya entregó el idToken.
  Future<void> _googleWithIdToken(String idToken) async {
    if (_loading || _googleLoading) return;
    setState(() => _googleLoading = true);
    try {
      final user = await AuthRepository.instance.signInWithGoogleIdToken(
        idToken,
      );
      if (mounted) enterApp(context, user);
    } on AuthException catch (e) {
      if (mounted) showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
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
    FocusScope.of(context).unfocus();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResetPasswordPage(initialEmail: _email.text.trim()),
      ),
    );
    if (changed ?? false) {
      _password.clear();
      _showMessage('Contraseña actualizada. Ingresa con la nueva.');
    }
  }

  void _showMessage(String message, {bool error = false, bool info = false}) {
    if (!mounted) return;
    showAppMessage(context, message, error: error, info: info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthLayout(
        header: const AuthHeader(
          title: 'Bienvenido',
          subtitle: 'Consulta pagos, inscripciones y comprobantes\nde tus hijos en un solo lugar.',
        ),
        child: Center(
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
                        onPressed: _googleLoading || !_ready ? null : _submit,
                      ),
                      const OrDivider(),
                      GoogleSignInArea(
                        loading: _googleLoading,
                        onPressed: _loading ? null : _google,
                        onWebIdToken: _googleWithIdToken,
                      ),
                      const SizedBox(height: 12),
                      AuthSwitchLink(
                        question: '¿No tienes cuenta?',
                        action: 'Regístrate',
                        onTap: () =>
                            Navigator.of(context).pushNamed(Routes.register),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
