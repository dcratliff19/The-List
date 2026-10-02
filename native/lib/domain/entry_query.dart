import 'entry.dart';

/// Every term must match; #terms match tags while plain terms search visible text.
class EntryQuery {
  final List<String> _terms;
  EntryQuery(String query)
    : _terms = query
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((term) => term.isNotEmpty)
          .toList();

  bool matches(Entry entry) {
    final content = [
      entry.title,
      entry.text('body'),
      entry.text('url'),
      entry.tags.join(' '),
      entry.text('description'),
    ].join(' ').toLowerCase();
    return _terms.every(
      (term) => term.startsWith('#')
          ? entry.tags.any(
              (tag) => tag.toLowerCase().contains(term.substring(1)),
            )
          : content.contains(term),
    );
  }
}
