import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../auth/data/app_user.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/validators.dart';
import '../../auth/presentation/widgets/auth_field.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../data/profile_review_store.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_ready.dart';

/// Correo (solo lectura) + nombres y apellidos editables. Los valores de
/// relleno que pone la API para cuentas de Google (p. ej. apellido
/// "GOOGLE") aparecen vacíos para obligar a escribir el dato real.
class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.user,
    required this.submitLabel,
    required this.onSubmit,
  });

  final AppUser user;
  final String submitLabel;

  /// Devuelve un mensaje de error para mostrar, o null si salió bien.
  final Future<String?> Function(ProfileInput input) onSubmit;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> with FormReady {
  final _formKey = GlobalKey<FormState>();
  late final _firstName = _controller(widget.user.firstName);
  late final _secondName = _controller(widget.user.secondName);
  late final _firstLastName = _controller(widget.user.firstLastName);
  late final _secondLastName = _controller(widget.user.secondLastName);
  bool _saving = false;

  TextEditingController _controller(String? value) => TextEditingController(
    text: ProfileReview.isPlaceholder(value, widget.user) ? '' : value,
  );

  bool get _ready =>
      Validators.name(_firstName.text, 'El nombre') == null &&
      Validators.optionalName(_secondName.text, 'El segundo nombre') == null &&
      Validators.name(_firstLastName.text, 'El apellido') == null &&
      Validators.optionalName(_secondLastName.text, 'El segundo apellido') ==
          null;

  @override
  void initState() {
    super.initState();
    watchFields([_firstName, _secondName, _firstLastName, _secondLastName]);
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _secondName,
      _firstLastName,
      _secondLastName,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final error = await widget.onSubmit(
      ProfileInput(
        firstName: _firstName.text.trim(),
        secondName: _secondName.text.trim(),
        firstLastName: _firstLastName.text.trim(),
        secondLastName: _secondLastName.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      showAppMessage(context, error, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadOnlyField(label: 'Correo electrónico', value: widget.user.email),
          gap,
          AuthField(
            label: 'Primer nombre',
            hint: 'Ej. Carlos',
            icon: Icons.person_outline_rounded,
            controller: _firstName,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.givenName],
            validator: (v) => Validators.name(v, 'El nombre'),
          ),
          gap,
          AuthField(
            label: 'Segundo nombre (opcional)',
            hint: 'Ej. Antonio',
            icon: Icons.person_outline_rounded,
            controller: _secondName,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.middleName],
            validator: (v) => Validators.optionalName(v, 'El segundo nombre'),
          ),
          gap,
          AuthField(
            label: 'Primer apellido',
            hint: 'Ej. Pérez',
            icon: Icons.person_outline_rounded,
            controller: _firstLastName,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.familyName],
            validator: (v) => Validators.name(v, 'El apellido'),
          ),
          gap,
          AuthField(
            label: 'Segundo apellido (opcional)',
            hint: 'Ej. Gómez',
            icon: Icons.person_outline_rounded,
            controller: _secondLastName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            validator: (v) => Validators.optionalName(v, 'El segundo apellido'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 28),
          LoadingButton(
            label: widget.submitLabel,
            loading: _saving,
            onPressed: _ready ? _submit : null,
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: AppColors.text, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.border.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.mail_outline_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
              const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
