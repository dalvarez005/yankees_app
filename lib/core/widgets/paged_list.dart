import 'package:flutter/material.dart';

import '../layout/responsive.dart';

import '../../app/app_colors.dart';
import 'app_ui.dart';

/// Trae la página [page] (desde 1) con hasta [pageSize] elementos.
typedef PageFetcher<T> = Future<List<T>> Function(int page, int pageSize);

/// Estado de una lista paginada: carga la primera página, trae más al llegar
/// al final y se reinicia al cambiar filtros ([refresh]).
///
/// "Hay más" se deduce de que la página llegó completa, así sirve con
/// cualquier endpoint paginado sin depender de `hasNext`.
class PagedController<T> extends ChangeNotifier {
  PagedController(this._fetch, {this.pageSize = 20});

  final PageFetcher<T> _fetch;
  final int pageSize;

  /// null mientras carga la primera página.
  List<T>? items;

  /// Error de la primera página (pantalla de error) …
  String? error;

  /// … o de una página siguiente (se reintenta desde el pie de la lista).
  String? moreError;
  bool loadingMore = false;
  bool hasNext = false;

  var _page = 0;

  /// Descarta respuestas de una búsqueda anterior que llegan tarde.
  var _generation = 0;
  var _disposed = false;

  /// Vuelve a la primera página (al abrir, al refrescar o al filtrar).
  /// Con [keepItems] no se muestra el esqueleto (deslizar para actualizar).
  Future<void> refresh({bool keepItems = false}) async {
    final generation = ++_generation;
    error = null;
    moreError = null;
    loadingMore = false;
    if (!keepItems) items = null;
    _notify();
    try {
      final page = await _fetch(1, pageSize);
      if (generation != _generation) return;
      items = [...page];
      _page = 1;
      hasNext = page.length >= pageSize;
    } catch (e) {
      if (generation != _generation) return;
      if (items == null || !keepItems) {
        items = null;
        error = _message(e);
      } else {
        moreError = _message(e);
      }
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (loadingMore || !hasNext || items == null) return;
    final generation = _generation;
    loadingMore = true;
    moreError = null;
    _notify();
    try {
      final page = await _fetch(_page + 1, pageSize);
      if (generation != _generation) return;
      items = [...items!, ...page];
      _page++;
      hasNext = page.length >= pageSize;
    } catch (e) {
      if (generation != _generation) return;
      moreError = _message(e);
    }
    loadingMore = false;
    _notify();
  }

  /// Cambios locales tras una acción (anular, validar…) sin recargar todo.
  void update(void Function(List<T> items) change) {
    final list = items;
    if (list == null) return;
    change(list);
    _notify();
  }

  // Las excepciones de los repositorios devuelven su mensaje en toString().
  static String _message(Object e) => e.toString();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Lista paginada: esqueleto, error, vacío, "deslizar para actualizar" y
/// carga automática de la siguiente página al acercarse al final.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.empty,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 32),
  });

  final PagedController<T> controller;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Se muestra cuando no hay resultados.
  final Widget empty;

  /// Arriba de la lista cuando hay datos (contador, resumen…).
  final Widget? header;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.centered(context, this.padding);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final items = c.items;
        final Widget child;
        if (items == null) {
          child = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            children: [
              if (c.error == null)
                const ListSkeleton()
              else
                ErrorState(message: c.error!, onRetry: c.refresh),
            ],
          );
        } else if (items.isEmpty) {
          child = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            children: [empty],
          );
        } else {
          final hasHeader = header != null;
          child = NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400) c.loadMore();
              return false;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: padding,
              itemCount: items.length + (hasHeader ? 1 : 0) + 1,
              itemBuilder: (context, i) {
                if (hasHeader && i == 0) return header!;
                final index = i - (hasHeader ? 1 : 0);
                if (index < items.length) {
                  return itemBuilder(context, items[index]);
                }
                return _Footer(controller: c, count: items.length);
              },
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => c.refresh(keepItems: true),
          color: AppColors.navy,
          child: child,
        );
      },
    );
  }
}

/// Pie de la lista: cargando más, error con reintento o fin de la lista.
class _Footer extends StatelessWidget {
  const _Footer({required this.controller, required this.count});

  final PagedController<Object?> controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.moreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              c.moreError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            TextButton.icon(
              onPressed: c.loadMore,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Cargar más'),
            ),
          ],
        ),
      );
    }
    if (c.hasNext) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.navy,
            ),
          ),
        ),
      );
    }
    // Solo se anuncia el final si hubo que paginar.
    if (count <= c.pageSize) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'Es todo · $count resultados',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
      ),
    );
  }
}
