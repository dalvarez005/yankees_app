import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_colors.dart';
import '../../auth/presentation/validators.dart';
import '../../auth/presentation/widgets/auth_field.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../../categories/data/category_repository.dart';
import '../data/dependent.dart';
import '../data/dependent_repository.dart';

/// Alta o edición de un hijo. Devuelve el [Dependent] guardado al cerrar.
class DependentFormPage extends StatefulWidget {
  const DependentFormPage({
    super.key,
    this.dependent,
    required this.categories,
  });

  /// Catálogo completo; se ofrecen las activas y, al editar, también la
  /// actual aunque esté inactiva.
  final List<Category> categories;

  /// null = agregar; con valor = editar.
  final Dependent? dependent;

  @override
  State<DependentFormPage> createState() => _DependentFormPageState();
}

class _DependentFormPageState extends State<DependentFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _cui = TextEditingController(text: widget.dependent?.cui);
  late final _firstName = TextEditingController(
    text: widget.dependent?.firstName,
  );
  late final _secondName = TextEditingController(
    text: widget.dependent?.secondName,
  );
  late final _firstLastName = TextEditingController(
    text: widget.dependent?.firstLastName,
  );
  late final _secondLastName = TextEditingController(
    text: widget.dependent?.secondLastName,
  );
  late int? _categoryId = widget.dependent?.categoryId;
  bool _saving = false;

  bool get _isEdit => widget.dependent != null;

  @override
  void dispose() {
    for (final c in [
      _cui,
      _firstName,
      _secondName,
      _firstLastName,
      _secondLastName,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final input = DependentInput(
      cui: _cui.text.replaceAll(' ', ''),
      firstName: _firstName.text.trim(),
      secondName: _secondName.text.trim(),
      firstLastName: _firstLastName.text.trim(),
      secondLastName: _secondLastName.text.trim(),
      categoryId: _categoryId!,
    );
    try {
      final repo = DependentRepository.instance;
      final saved = _isEdit
          ? await repo.update(widget.dependent!.id, input)
          : await repo.add(input);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on DependentException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Atrás',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_isEdit ? 'Editar hijo' : 'Agregar hijo'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthField(
                      label: 'CUI',
                      hint: '13 dígitos del DPI o certificado',
                      icon: Icons.badge_outlined,
                      controller: _cui,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(13),
                      ],
                      validator: Validators.cui,
                    ),
                    gap,
                    AuthField(
                      label: 'Primer nombre',
                      hint: 'Ej. Sofía',
                      icon: Icons.person_outline_rounded,
                      controller: _firstName,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => Validators.name(v, 'El nombre'),
                    ),
                    gap,
                    AuthField(
                      label: 'Segundo nombre (opcional)',
                      hint: 'Ej. Isabel',
                      icon: Icons.person_outline_rounded,
                      controller: _secondName,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          Validators.optionalName(v, 'El segundo nombre'),
                    ),
                    gap,
                    AuthField(
                      label: 'Primer apellido',
                      hint: 'Ej. Castro',
                      icon: Icons.person_outline_rounded,
                      controller: _firstLastName,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => Validators.name(v, 'El apellido'),
                    ),
                    gap,
                    AuthField(
                      label: 'Segundo apellido (opcional)',
                      hint: 'Ej. Méndez',
                      icon: Icons.person_outline_rounded,
                      controller: _secondLastName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      validator: (v) =>
                          Validators.optionalName(v, 'El segundo apellido'),
                    ),
                    gap,
                    _CategoryField(
                      categories: [
                        for (final c in widget.categories)
                          if (c.active || c.id == widget.dependent?.categoryId)
                            c,
                      ],
                      value: _categoryId,
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                    const SizedBox(height: 28),
                    LoadingButton(
                      label: _isEdit ? 'Guardar cambios' : 'Agregar',
                      loading: _saving,
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField({
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  final List<Category> categories;

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categoría',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: AppColors.text, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: value,
          onChanged: onChanged,
          validator: (v) => v == null ? 'Elige una categoría' : null,
          decoration: const InputDecoration(
            hintText: 'Selecciona',
            prefixIcon: Icon(Icons.sports_baseball_outlined, size: 20),
          ),
          borderRadius: BorderRadius.circular(14),
          items: [
            for (final c in categories)
              DropdownMenuItem(
                value: c.id,
                child: Text(c.active ? c.name : '${c.name} (inactiva)'),
              ),
          ],
        ),
      ],
    );
  }
}
