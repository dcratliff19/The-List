import 'json.dart';

/// Materialized entry data; the repository stores revisions for each field.
class Entry {
  final String id, project, kind;
  final Json fields;
  Entry(this.id, this.project, this.kind, this.fields);
  String text(String key) => fields[key]?.toString() ?? '';
  bool flag(String key) => fields[key] == true;
  List<String> get tags => parseTags(text('tags'));
  static List<String> parseTags(String text) {
    final seen = <String>{};
    return text
        .split(RegExp(r'[\s,]+'))
        .map((tag) => tag.replaceFirst(RegExp(r'^#+'), ''))
        .where((tag) => tag.isNotEmpty && seen.add(tag.toLowerCase()))
        .toList();
  }

  static const currencies = ['USD', 'EUR', 'GBP', 'CAD', 'AUD'];
  static int? parsePrice(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(text)) {
      throw const FormatException(
        'Enter a positive price with up to two decimal places, or leave blank.',
      );
    }
    final parts = text.split('.');
    return int.parse(parts[0]) * 100 +
        int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  }

  static String amount(int cents) =>
      '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
  int? get priceMinor => parsePrice(text('price'));
  String get currency =>
      currencies.contains(text('currency')) ? text('currency') : 'USD';
  String get priceLabel =>
      priceMinor == null ? '' : '$currency ${amount(priceMinor!)}';
  int get quantity => (fields['quantity'] as int?) ?? 1;
  String get title => text('title');
  bool get deleted => flag('deleted');
  Json toJson() => {
    'id': id,
    'project': project,
    'kind': kind,
    'fields': fields,
  };
}
