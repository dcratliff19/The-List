import 'dart:convert';
import 'entry.dart';
import 'json.dart';

/// Validates the versioned operation boundary before any database mutations.
void validateOperation(Json op) {
  if (![
        'project',
        'link',
        'note',
        'photo',
        'reminder',
        'check',
        'comment',
      ].contains(op['kind']) ||
      op['id'] is! String ||
      op['entity'] is! String ||
      op['project'] is! String ||
      op['device'] is! String ||
      op['counter'] is! int ||
      op['fields'] is! Map) {
    throw const FormatException('Invalid project data');
  }
  if ((op['counter'] as int) < 0 ||
      (op['counter'] as int) > 9007199254740000 ||
      jsonEncode(op).length > 262144) {
    throw const FormatException('Project data exceeds limits');
  }
  for (final key in ['id', 'entity', 'project', 'device']) {
    if ((op[key] as String).isEmpty || (op[key] as String).length > 128) {
      throw const FormatException('Invalid identity');
    }
  }
  if (op['kind'] == 'project' && op['entity'] != op['project']) {
    throw const FormatException('Invalid project identity');
  }
  const strings = {
    'title',
    'body',
    'description',
    'url',
    'tags',
    'photo',
    'cover',
    'due',
    'zone',
    'target',
    'created',
    'label',
    'previewTitle',
    'previewDescription',
    'previewError',
    'previewStatus',
    'boardStatus',
    'price',
    'currency',
    'budget',
    'budgetCurrency',
    'columns',
    'assignee',
    'purchaseStatus',
    'comparison',
    'repeat',
    'lastCompleted',
    'author',
    'modified',
    'base',
  };
  const flags = {'deleted', 'archived', 'favorite', 'example', 'done', 'inbox'};
  (op['fields'] as Map).forEach((key, value) {
    if (key == 'price' || key == 'budget') {
      if (value is! String) throw const FormatException('Invalid price');
      Entry.parsePrice(value);
    }
    if (['currency', 'budgetCurrency'].contains(key) &&
        !Entry.currencies.contains(value)) {
      throw const FormatException('Invalid currency');
    }
    if (strings.contains(key)) {
      if (value is! String || value.length > 50000) {
        throw const FormatException('Invalid text field');
      }
    } else if (flags.contains(key)) {
      if (value is! bool) throw const FormatException('Invalid flag');
    } else if (['quantity', 'rank', 'repeatDay'].contains(key)) {
      if (value is! int ||
          value < 0 ||
          value > 1000000 ||
          (key == 'quantity' && value < 1)) {
        throw const FormatException('Invalid quantity or order');
      }
    } else if (key == 'color') {
      if (value is! int || value < 0 || value > 0xffffffff) {
        throw const FormatException('Invalid color');
      }
    } else {
      throw const FormatException('Unknown project field');
    }
    if (key == 'columns' && value != '') {
      final columns = jsonDecode(value as String);
      if (columns is! Map ||
          columns.isEmpty ||
          columns.length > 20 ||
          columns.entries.any(
            (e) =>
                e.key is! String ||
                (e.key as String).isEmpty ||
                (e.key as String).length > 128 ||
                e.value is! String ||
                (e.value as String).trim().isEmpty ||
                (e.value as String).length > 60,
          )) {
        throw const FormatException('Invalid board columns');
      }
    }
    if (key == 'repeat' &&
        ![
          '',
          'none',
          'daily',
          'weekly',
          'monthly',
          'days:1,2,3,4,5',
        ].contains(value)) {
      throw const FormatException('Invalid reminder recurrence');
    }
    if (key == 'base') {
      final bases = jsonDecode(value as String);
      if (bases is! Map ||
          bases.values.any(
            (v) =>
                v is! List ||
                v.length != 3 ||
                v[0] is! int ||
                v[1] is! String ||
                v[2] is! String,
          )) {
        throw const FormatException('Invalid revision ancestry');
      }
    }
    if ((key == 'photo' || key == 'cover') &&
        value != '' &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value as String)) {
      throw const FormatException('Invalid photo reference');
    }
  });
}
