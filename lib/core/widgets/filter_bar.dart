import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_colors.dart';

/// Una opción de un filtro. [value] null = "Todos".
class FilterChoice {
  const FilterChoice(this.value, this.label);
  final Object? value;
  final String label;
}

/// Un filtro de selección única (estado, tipo, categoría…).
class FilterSpec {
  const FilterSpec({
    required this.key,
    required this.title,
    required this.choices,
    this.icon = Icons.tune_rounded,
  });

  /// Clave en el mapa de valores.
  final String key;
  final String title;

  /// Sin la opción "Todos": se agrega sola.
  final List<FilterChoice> choices;
  final IconData icon;

  String? labelOf(Object? value) => value == null
      ? null
      : choices.where((c) => c.value == value).map((c) => c.label).firstOrNull;
}

/// Buscador + botón "Filtros" (con contador) que abre una hoja con todos los
/// filtros. Los filtros activos se muestran como etiquetas que se quitan
/// con un toque.
class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    required this.onChanged,
    this.searchHint,
    this.filters = const [],
    this.values = const {},
    this.search = '',
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 4),
  });

  /// null oculta el buscador.
  final String? searchHint;
  final List<FilterSpec> filters;

  /// Valor actual de cada filtro por [FilterSpec.key] (ausente = todos).
  final Map<String, Object?> values;
  final String search;

  /// Texto de búsqueda (ya recortado) y filtros elegidos.
  final void Function(String search, Map<String, Object?> values) onChanged;
  final EdgeInsets padding;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final _search = TextEditingController(text: widget.search);
  Timer? _debounce;

  Map<String, Object?> get _active => {
    for (final e in widget.values.entries)
      if (e.value != null) e.key: e.value,
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _emit(Map<String, Object?> values) =>
      widget.onChanged(_search.text.trim(), values);

  /// Busca al dejar de escribir, sin esperar a "Enter".
  void _onSearchChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _emit(_active));
  }

  void _submit() {
    _debounce?.cancel();
    _emit(_active);
  }

  Future<void> _openSheet() async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(filters: widget.filters, values: _active),
    );
    if (result != null) {
      _debounce?.cancel();
      _emit(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final hasSearch = widget.searchHint != null;
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasSearch)
                Expanded(
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Borrar búsqueda',
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                                _submit();
                              },
                            ),
                    ),
                  ),
                ),
              if (widget.filters.isNotEmpty) ...[
                if (hasSearch) const SizedBox(width: 10),
                if (hasSearch)
                  _FilterButton(count: active.length, onTap: _openSheet)
                else
                  // Sin buscador, el botón ocupa todo el ancho.
                  Expanded(
                    child: _FilterButton(
                      count: active.length,
                      onTap: _openSheet,
                    ),
                  ),
              ],
            ],
          ),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final spec in widget.filters)
                  if (active[spec.key] != null)
                    InputChip(
                      label: Text(
                        spec.labelOf(active[spec.key]) ?? spec.title,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      avatar: Icon(spec.icon, size: 16, color: AppColors.navy),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      deleteIconColor: AppColors.navy,
                      onDeleted: () => _emit({...active}..remove(spec.key)),
                      backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                if (active.length > 1)
                  ActionChip(
                    label: const Text(
                      'Quitar filtros',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    onPressed: () => _emit(const {}),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = count > 0;
    return Tooltip(
      message: 'Filtros',
      child: Material(
        color: on ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? AppColors.navy : AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: on ? Colors.white : AppColors.navy,
                ),
                const SizedBox(width: 6),
                Text(
                  on ? 'Filtros · $count' : 'Filtros',
                  style: TextStyle(
                    color: on ? Colors.white : AppColors.navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja con todos los filtros; nada se aplica hasta tocar "Aplicar".
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.filters, required this.values});

  final List<FilterSpec> filters;
  final Map<String, Object?> values;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final _values = {...widget.values};

  Widget _choice(FilterSpec spec, FilterChoice choice) {
    final selected = _values[spec.key] == choice.value;
    return ChoiceChip(
      label: Text(choice.label),
      selected: selected,
      onSelected: (_) => setState(() {
        if (choice.value == null) {
          _values.remove(spec.key);
        } else {
          _values[spec.key] = choice.value;
        }
      }),
      selectedColor: AppColors.navy,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.text,
        fontWeight: FontWeight.w500,
      ),
      showCheckmark: false,
      side: BorderSide(color: selected ? AppColors.navy : AppColors.border),
      backgroundColor: AppColors.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Filtros',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _values.isEmpty
                      ? null
                      : () => setState(_values.clear),
                  child: const Text('Limpiar'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              children: [
                for (final spec in widget.filters) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Row(
                      children: [
                        Icon(spec.icon, size: 18, color: AppColors.textMuted),
                        const SizedBox(width: 8),
                        Text(
                          spec.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _choice(spec, const FilterChoice(null, 'Todos')),
                      for (final c in spec.choices) _choice(spec, c),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_values),
              child: Text(
                _values.isEmpty
                    ? 'Ver todos'
                    : 'Aplicar ${_values.length} '
                          '${_values.length == 1 ? 'filtro' : 'filtros'}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
