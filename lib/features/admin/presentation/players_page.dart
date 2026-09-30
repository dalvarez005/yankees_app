import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/access/permissions.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feedback.dart';
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
  final _search = TextEditingController();
  List<Player>? _players;
  List<Category> _categories = const [];
  int? _categoryId;
  String? _error;
  Timer? _debounce;

  /// Evita que una respuesta vieja pise a la del último filtro.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCategories();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() => _error = null);
    try {
      final players = await AdminRepository.instance.players(
        categoryId: _categoryId,
        search: _search.text,
      );
      if (mounted && request == _request) setState(() => _players = players);
    } on AdminException catch (e) {
      if (mounted && request == _request) setState(() => _error = e.message);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final list = await CategoryRepository.instance.list();
      if (mounted) {
        setState(() => _categories = [...list.where((c) => c.active)]);
      }
    } on CategoryException {
      // Sin chips: se puede buscar igual.
    }
  }

  void _setCategory(int? id) {
    setState(() {
      _categoryId = id;
      _players = null;
    });
    _load();
  }

  void _onSearch(String _) {
    setState(() {}); // Botón de limpiar.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Widget _chip(String label, int? id) {
    final selected = _categoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _setCategory(id),
        selectedColor: AppColors.navy,
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.text,
          fontWeight: FontWeight.w500,
        ),
        showCheckmark: false,
        side: const BorderSide(color: AppColors.border),
        backgroundColor: AppColors.surface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.can(Permissions.playersView)) return const NoAccessView();
    final q = _search.text.trim();
    final players = _players ?? const <Player>[];
    final groups = <String, List<Player>>{};
    for (final p in players) {
      (groups[p.categoryName ?? 'Sin categoría'] ??= []).add(p);
    }
    final names = groups.keys.toList()..sort();
    for (final list in groups.values) {
      list.sort((a, b) => a.fullName.compareTo(b.fullName));
    }
    final filtered = q.isNotEmpty || _categoryId != null;

    return Scaffold(
      appBar: pageAppBar(context, 'Jugadores'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                _debounce?.cancel();
                _load();
              },
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o CUI',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _debounce?.cancel();
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          if (_categories.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                children: [
                  _chip('Todas', null),
                  for (final c in _categories) _chip(c.name, c.id),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.navy,
              child: AsyncListView(
                loading: _players == null,
                error: _error,
                onRetry: _load,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                header: players.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          players.length == 1
                              ? '1 jugador'
                              : '${players.length} jugadores',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                empty: EmptyState(
                  icon: Icons.sports_baseball_outlined,
                  title: filtered ? 'Sin resultados' : 'Aún no hay jugadores',
                  message: filtered
                      ? 'Ningún jugador coincide con el filtro.'
                      : 'Cuando los padres registren a sus hijos aparecerán '
                            'aquí.',
                ),
                children: [
                  for (final name in names) ...[
                    ListHeader(name, count: groups[name]!.length),
                    for (final p in groups[name]!) _PlayerTile(player: p),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
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
          if (p.age != null)
            Pill(p.age == 1 ? '1 año' : '${p.age} años', tone: PillTone.brand),
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
