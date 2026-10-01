import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yankees/app/app_theme.dart';
import 'package:yankees/core/paging/page_of.dart';
import 'package:yankees/core/widgets/filter_bar.dart';
import 'package:yankees/core/widgets/paged_list.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('pageOf', () {
    final all = [for (var i = 1; i <= 45; i++) i];

    test('corta por página y la última queda incompleta', () {
      expect(pageOf(all, 1, 20), [for (var i = 1; i <= 20; i++) i]);
      expect(pageOf(all, 3, 20), [41, 42, 43, 44, 45]);
      expect(pageOf(all, 4, 20), isEmpty);
    });
  });

  group('PagedController', () {
    PagedController<int> controller(List<int> all, {List<int>? calls}) =>
        PagedController<int>((page, size) async {
          calls?.add(page);
          return pageOf(all, page, size);
        }, pageSize: 20);

    test('carga la primera página y trae más hasta el final', () async {
      final calls = <int>[];
      final c = controller([for (var i = 0; i < 45; i++) i], calls: calls);
      expect(c.items, isNull);

      await c.refresh();
      expect(c.items, hasLength(20));
      expect(c.hasNext, isTrue);

      await c.loadMore();
      expect(c.items, hasLength(40));
      await c.loadMore();
      expect(c.items, hasLength(45));
      expect(c.hasNext, isFalse);

      // Ya no hay más: no vuelve a pedir.
      await c.loadMore();
      expect(calls, [1, 2, 3]);
    });

    test('una página exacta pide una más y descubre el final', () async {
      final c = controller([for (var i = 0; i < 20; i++) i]);
      await c.refresh();
      expect(c.hasNext, isTrue);
      await c.loadMore();
      expect(c.items, hasLength(20));
      expect(c.hasNext, isFalse);
    });

    test('refrescar descarta la respuesta vieja que llega tarde', () async {
      final slow = Completer<List<int>>();
      var call = 0;
      final c = PagedController<int>((page, size) {
        call++;
        return call == 1 ? slow.future : Future.value([7, 8]);
      });
      final first = c.refresh(); // búsqueda vieja, lenta
      await c.refresh(); // filtro nuevo
      expect(c.items, [7, 8]);
      slow.complete([1, 2, 3]);
      await first;
      expect(c.items, [7, 8]);
    });

    test('error en la primera página y en las siguientes', () async {
      var fail = true;
      final c = PagedController<int>((page, size) async {
        if (fail) throw Exception('sin conexión');
        return pageOf([for (var i = 0; i < 30; i++) i], page, size);
      }, pageSize: 20);

      await c.refresh();
      expect(c.items, isNull);
      expect(c.error, contains('sin conexión'));

      fail = false;
      await c.refresh();
      expect(c.items, hasLength(20));

      fail = true;
      await c.loadMore();
      // Lo ya cargado se conserva; el error va al pie de la lista.
      expect(c.items, hasLength(20));
      expect(c.moreError, contains('sin conexión'));

      fail = false;
      await c.loadMore();
      expect(c.items, hasLength(30));
      expect(c.moreError, isNull);
    });

    test('update aplica cambios locales sin recargar', () async {
      final calls = <int>[];
      final c = controller([1, 2, 3], calls: calls);
      await c.refresh();
      c.update((items) => items.remove(2));
      expect(c.items, [1, 3]);
      expect(calls, [1]);
    });
  });

  group('PagedListView', () {
    testWidgets('al llegar al final carga la página siguiente', (tester) async {
      final c = PagedController<int>(
        (page, size) async =>
            pageOf([for (var i = 0; i < 50; i++) i], page, size),
        pageSize: 20,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PagedListView<int>(
              controller: c,
              empty: const Text('vacío'),
              itemBuilder: (_, i) =>
                  SizedBox(height: 80, child: Text('Fila $i')),
            ),
          ),
        ),
      );
      unawaited(c.refresh());
      await tester.pumpAndSettle();
      expect(find.text('Fila 0'), findsOneWidget);
      expect(c.items, hasLength(20));

      await tester.fling(find.byType(ListView), const Offset(0, -3000), 5000);
      await tester.pumpAndSettle();
      expect(c.items!.length, greaterThan(20));

      await tester.fling(find.byType(ListView), const Offset(0, -9000), 9000);
      await tester.pumpAndSettle();
      await tester.fling(find.byType(ListView), const Offset(0, -9000), 9000);
      await tester.pumpAndSettle();
      expect(c.items, hasLength(50));
      expect(find.text('Es todo · 50 resultados'), findsOneWidget);
    });

    testWidgets('sin resultados muestra el estado vacío', (tester) async {
      final c = PagedController<int>((_, _) async => const []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagedListView<int>(
              controller: c,
              empty: const Text('Nada por aquí'),
              itemBuilder: (_, i) => Text('$i'),
            ),
          ),
        ),
      );
      unawaited(c.refresh());
      await tester.pumpAndSettle();
      expect(find.text('Nada por aquí'), findsOneWidget);
    });
  });

  group('FilterBar', () {
    const specs = [
      FilterSpec(
        key: 'status',
        title: 'Estado',
        choices: [FilterChoice('P', 'Por pagar'), FilterChoice('A', 'Pagados')],
      ),
      FilterSpec(
        key: 'type',
        title: 'Tipo',
        choices: [FilterChoice('M', 'Mensualidad')],
      ),
    ];

    Future<List<(String, Map<String, Object?>)>> pump(
      WidgetTester tester, {
      String? hint = 'Buscar',
    }) async {
      final changes = <(String, Map<String, Object?>)>[];
      var values = <String, Object?>{};
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => FilterBar(
                searchHint: hint,
                filters: specs,
                values: values,
                onChanged: (search, v) {
                  changes.add((search, v));
                  setState(() => values = v);
                },
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('elegir en la hoja y aplicar; el botón cuenta los activos', (
      tester,
    ) async {
      final changes = await pump(tester);
      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Por pagar'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mensualidad'));
      await tester.pumpAndSettle();
      // Nada se aplica hasta confirmar.
      expect(changes, isEmpty);
      await tester.tap(find.text('Aplicar 2 filtros'));
      await tester.pumpAndSettle();

      expect(changes.single.$2, {'status': 'P', 'type': 'M'});
      expect(find.text('Filtros · 2'), findsOneWidget);
      // Etiquetas de los filtros activos.
      expect(find.widgetWithText(InputChip, 'Por pagar'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Mensualidad'), findsOneWidget);
    });

    testWidgets('quitar un filtro desde su etiqueta', (tester) async {
      final changes = await pump(tester);
      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Pagados'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar 1 filtro'));
      await tester.pumpAndSettle();

      final chip = find.widgetWithText(InputChip, 'Pagados');
      await tester.tap(
        find.descendant(of: chip, matching: find.byIcon(Icons.close_rounded)),
      );
      await tester.pumpAndSettle();
      expect(changes.last.$2, isEmpty);
      expect(find.text('Filtros'), findsOneWidget);
    });

    testWidgets('buscar espera a que se deje de escribir', (tester) async {
      final changes = await pump(tester);
      await tester.enterText(find.byType(TextField), ' so');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), ' sofia ');
      await tester.pump(const Duration(milliseconds: 200));
      expect(changes, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      expect(changes.single.$1, 'sofia');
    });

    testWidgets('sin buscador el botón ocupa el ancho y no rompe el layout', (
      tester,
    ) async {
      await pump(tester, hint: null);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Filtros'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
