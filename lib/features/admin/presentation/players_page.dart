import 'package:flutter/material.dart';

import '../../../core/access/permissions.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/paged_list.dart';
import '../../auth/data/app_user.dart';
import '../../categories/data/category_repository.dart';
import '../data/admin_repository.dart';

/// Todos los jugadores del club (requiere `jugadores.ver`), filtrados en la
/// API por categoría y por nombre o CUI, con su padre y si está solvente.
class PlayersPage extends StatefulWidget {
  const PlayersPage({super.key, required this.user});

  final AppUser user;

  @override
  State<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<PlayersPage> {
  List<Category> _categories = const [];
  String _search = '';
  Map<String, Object?> _filters = const {};

  late final _list = PagedController<Player>(
    (page, pageSize) => AdminRepository.instance.players(
      categoryId: _filters['category'] as int?,
      search: _search,
      page: page,
      pageSize: pageSize,
    ),
  );

  @override
  void initState() {
    super.initState();
    _list.refresh();
    _loadCategories();
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final list = await CategoryRepository.instance.list();
      if (mounted) {
        setState(() => _categories = [...list.where((c) => c.active)]);
      }
    } on CategoryException {
      // Sin filtro de categoría: se puede buscar igual.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.playersView)) return const NoAccessView();
    final filtered = _search.isNotEmpty || _filters.isNotEmpty;
    return Scaffold(
      appBar: pageAppBar(context, 'Jugadores'),
      body: Column(
        children: [
          FilterBar(
            searchHint: 'Buscar por nombre o CUI',
            filters: [
              if (_categories.isNotEmpty)
                FilterSpec(
                  key: 'category',
                  title: 'Categoría',
                  icon: Icons.sports_baseball_outlined,
                  choices: [
                    for (final c in _categories) FilterChoice(c.id, c.name),
                  ],
                ),
            ],
            values: _filters,
            search: _search,
            onChanged: (search, values) {
              setState(() {
                _search = search;
                _filters = values;
              });
              _list.refresh();
            },
          ),
          Expanded(
            child: PagedListView<Player>(
              controller: _list,
              empty: EmptyState(
                icon: Icons.sports_baseball_outlined,
                title: filtered ? 'Sin resultados' : 'Aún no hay jugadores',
                message: filtered
                    ? 'Ningún jugador coincide con la búsqueda o el filtro.'
                    : 'Cuando los padres registren a sus hijos aparecerán '
                          'aquí.',
              ),
              itemBuilder: (context, p) => _PlayerTile(player: p),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return ListCard(
      leading: AppAvatar(
        seed: p.cui ?? p.fullName,
        initials: [
          p.name,
          p.lastName,
        ].where((s) => s.isNotEmpty).map((s) => s[0].toUpperCase()).join(),
      ),
      title: p.fullName,
      subtitle: [
        if (p.cui != null) 'CUI ${p.cui}',
        if (p.parentName != null) 'Padre/madre: ${p.parentName}',
      ].join('\n'),
      subtitleLines: 2,
      footer: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (p.categoryName != null)
            Pill(
              p.categoryName!,
              tone: PillTone.brand,
              icon: Icons.sports_baseball_outlined,
            ),
          if (p.age != null) Pill(p.age == 1 ? '1 año' : '${p.age} años'),
          if (p.parentSolvent == true)
            const Pill(
              'Solvente',
              tone: PillTone.success,
              icon: Icons.verified_rounded,
            )
          else if (p.parentSolvent == false)
            const Pill(
              'Insolvente',
              tone: PillTone.danger,
              icon: Icons.warning_amber_rounded,
            ),
        ],
      ),
    );
  }
}
