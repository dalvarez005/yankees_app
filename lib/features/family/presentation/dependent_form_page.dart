import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_colors.dart';
import '../../auth/presentation/validators.dart';
import '../../auth/presentation/widgets/auth_field.dart';
import '../../auth/presentation/widgets/loading_button.dart';
import '../../../core/format/formats.dart';
import '../../categories/data/category_repository.dart';
import '../data/dependent.dart';
import '../data/dependent_repository.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/form_ready.dart';

/// Alta o edición de un hijo. Devuelve el [Dependent] guardado al cerrar.
///
/// Se pide la fecha de nacimiento; la API calcula la edad y asigna la
/// categoría según los rangos de edad del club.
class DependentFormPage extends StatefulWidget {
  const DependentFormPage({
    super.key,
    this.dependent,
    this.categories = const [],
  });

  /// Catálogo con los rangos de edad, para mostrar qué categoría tocará.
  final List<Category> categories;

  /// null = agregar; con valor = editar.
  final Dependent? dependent;

  @override
  State<DependentFormPage> createState() => _DependentFormPageState();
}

class _DependentFormPageState extends State<DependentFormPage> with FormReady {
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
  late DateTime? _birthDate = widget.dependent?.birthDate;
  bool _saving = false;

  bool get _isEdit => widget.dependent != null;

  /// Hay rangos configurados: se puede anticipar la categoría.
  bool get _canPreview =>
      widget.categories.any((c) => c.active && c.hasAgeRange);

  int? get _age =>
      _birthDate == null ? null : ageAt(_birthDate!, DateTime.now());

  /// Categoría que asignará la API; null si ninguna cubre la edad.
  Category? get _category {
    final age = _age;
    return age == null ? null : categoryForAge(widget.categories, age);
  }

  /// Con la fecha elegida no hay categoría para esa edad.
  bool get _outOfRange => _canPreview && _age != null && _category == null;

  /// Todo lo escrito está bien: solo falta (si falta) la fecha.
  bool get _textReady =>
      Validators.cui(_cui.text) == null &&
      Validators.name(_firstName.text, 'El nombre') == null &&
      Validators.optionalName(_secondName.text, 'El segundo nombre') == null &&
      Validators.name(_firstLastName.text, 'El apellido') == null &&
      Validators.optionalName(_secondLastName.text, 'El segundo apellido') ==
          null;

  bool get _ready => _textReady && _birthDate != null && !_outOfRange;

  @override
  void initState() {
    super.initState();
    watchFields([
      _cui,
      _firstName,
      _secondName,
      _firstLastName,
      _secondLastName,
    ]);
  }

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
      birthDate: _birthDate!,
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
      showAppMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _outOfRangeMessage {
    final ranges = [
      for (final c in widget.categories)
        if (c.active && c.hasAgeRange) c,
    ];
    final min = ranges.map((c) => c.ageFrom!).reduce((a, b) => a < b ? a : b);
    final max = ranges.map((c) => c.ageTo!).reduce((a, b) => a > b ? a : b);
    return 'El club no tiene una categoría para $_age '
        '${_age == 1 ? 'año' : 'años'}. Las categorías van de $min a $max años.';
  }

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 8, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Fecha de nacimiento',
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
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
                autovalidateMode: AutovalidateMode.onUserInteraction,
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
                      validator: (v) =>
                          Validators.optionalName(v, 'El segundo apellido'),
                    ),
                    gap,
                    _BirthDateField(
                      value: _birthDate,
                      onTap: _saving ? null : _pickBirthDate,
                      // En rojo cuando es lo único que falta para guardar.
                      highlightMissing: _textReady,
                    ),
                    gap,
                    _CategoryInfo(
                      name: _canPreview
                          ? _category?.name
                          : (_isEdit &&
                                    _birthDate == widget.dependent!.birthDate
                                ? widget.dependent!.categoryName
                                : null),
                      error: _outOfRange ? _outOfRangeMessage : null,
                    ),
                    const SizedBox(height: 28),
                    LoadingButton(
                      label: _isEdit ? 'Guardar cambios' : 'Agregar',
                      loading: _saving,
                      onPressed: _ready ? _save : null,
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

class _BirthDateField extends StatelessWidget {
  const _BirthDateField({
    required this.value,
    required this.onTap,
    required this.highlightMissing,
  });

  final DateTime? value;
  final VoidCallback? onTap;

  /// Sin fecha: el aviso de obligatoria pasa a rojo.
  final bool highlightMissing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final date = value;
    final age = date == null ? null : ageAt(date, DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fecha de nacimiento',
          style: text.labelLarge?.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.cake_outlined, size: 20),
              suffixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
              errorText: date == null && highlightMissing
                  ? 'La fecha de nacimiento es obligatoria'
                  : null,
              helperText: date == null && !highlightMissing
                  ? 'Obligatoria'
                  : null,
            ),
            child: Text(
              date == null
                  ? 'Selecciona la fecha'
                  : '${formatDate(date)} · ${age == 1 ? '1 año' : '$age años'}',
              style: text.bodyLarge?.copyWith(
                color: date == null ? AppColors.textMuted : AppColors.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Categoría solo informativa: la asigna la API según la edad.
class _CategoryInfo extends StatelessWidget {
  const _CategoryInfo({required this.name, required this.error});

  /// Categoría que corresponde; null si todavía no se sabe.
  final String? name;

  /// La edad no cae en ninguna categoría.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = name;
    final e = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categoría',
          style: text.labelLarge?.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: InputDecoration(
            enabled: false,
            prefixIcon: Icon(
              e == null
                  ? Icons.sports_baseball_outlined
                  : Icons.error_outline_rounded,
              size: 20,
              color: e == null ? null : AppColors.error,
            ),
          ),
          child: Text(
            e != null
                ? 'Sin categoría para esa edad'
                : n ?? 'Se asigna según la fecha de nacimiento',
            style: text.bodyLarge?.copyWith(
              color: e != null
                  ? AppColors.error
                  : n == null
                  ? AppColors.textMuted
                  : AppColors.text,
              fontWeight: n == null && e == null ? null : FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          e ?? 'El club asigna la categoría automáticamente según la edad.',
          style: text.bodySmall?.copyWith(
            color: e == null ? AppColors.textMuted : AppColors.error,
          ),
        ),
      ],
    );
  }
}
