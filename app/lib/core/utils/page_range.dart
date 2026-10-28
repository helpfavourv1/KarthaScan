/// Reads a page choice such as "1-3, 5" or "all" into zero-based page numbers.
///
/// Pages are counted from 1 in what the person types. Returns null when the text
/// is empty or anything in it is not a page of a [total]-page document, so a typo
/// is reported instead of being half-applied.
List<int>? parsePageRange(String spec, int total) {
  final String text = spec.trim().toLowerCase();
  if (text.isEmpty || total < 1) return null;
  if (text == 'all') return <int>[for (int i = 0; i < total; i++) i];
  final Set<int> pages = <int>{};
  for (final String raw in text.split(RegExp(r'[,;\s]+'))) {
    if (raw.isEmpty) continue;
    final RegExpMatch? range = RegExp(r'^(\d+)\s*[-–]\s*(\d+)$').firstMatch(raw);
    if (range != null) {
      final int a = int.parse(range.group(1)!), b = int.parse(range.group(2)!);
      if (a < 1 || b > total || a > b) return null;
      for (int i = a; i <= b; i++) {
        pages.add(i - 1);
      }
      continue;
    }
    final int? n = int.tryParse(raw);
    if (n == null || n < 1 || n > total) return null;
    pages.add(n - 1);
  }
  if (pages.isEmpty) return null;
  return pages.toList()..sort();
}
