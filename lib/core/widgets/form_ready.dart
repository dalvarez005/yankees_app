import 'package:flutter/widgets.dart';

/// Para formularios cuyo botón se habilita solo cuando lo obligatorio está
/// completo: reconstruye la pantalla cada vez que cambia un campo observado.
///
/// Cada formulario define su propio `_ready` con los mismos validadores de
/// los campos, y pasa `onPressed: _ready ? _guardar : null`.
mixin FormReady<T extends StatefulWidget> on State<T> {
  final _watched = <Listenable>[];

  /// Llamar en `initState` con los controladores de los campos.
  void watchFields(Iterable<Listenable> fields) {
    for (final f in fields) {
      f.addListener(_onFieldChanged);
      _watched.add(f);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final f in _watched) {
      f.removeListener(_onFieldChanged);
    }
    super.dispose();
  }
}
