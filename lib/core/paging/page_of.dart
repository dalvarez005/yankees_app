/// Página [page] (desde 1) de una lista en memoria: para repositorios
/// simulados o endpoints que devuelven todo de una vez.
List<T> pageOf<T>(List<T> all, int page, int pageSize) {
  final start = (page - 1) * pageSize;
  if (start < 0 || start >= all.length) return const [];
  return all.sublist(start, (start + pageSize).clamp(0, all.length));
}
