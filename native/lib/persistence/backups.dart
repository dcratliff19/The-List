part of '../store.dart';

/// Portable snapshots retain historical attachments and exclude secure pairing keys.
extension _StoreBackups on Store {
  Future<String> _exportData({Set<String>? projects}) async {
    final ops = db
        .select('SELECT * FROM operations')
        .map(_operation)
        .where((o) => projects == null || projects.contains(o['project']))
        .toList();
    // Capture metadata before awaiting file reads. Include historical references
    // so restoring an earlier photo revision after import still works.
    final savedTemplates = projects == null ? templates : null;
    final hashes = ops
        .expand(
          (op) => ['photo', 'cover'].map((key) => (op['fields'] as Map)[key]),
        )
        .whereType<String>()
        .where((hash) => hash.isNotEmpty)
        .toSet();
    final photos = <String, String>{};
    var total = 0;
    for (final hash in hashes) {
      final file = blob(hash);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        total += bytes.length;
        if (total > 100 * 1024 * 1024) {
          throw const FormatException(
            'This portable backup exceeds 100 MB of photos. Copy the local workspace folder for a complete backup.',
          );
        }
        photos[hash] = base64Encode(bytes);
      }
    }
    return jsonEncode({
      'format': 'the-list',
      'version': 1,
      'operations': ops,
      'photos': photos,
      'templates': ?savedTemplates,
    });
  }

  Future<void> _importFrom(
    File file, {
    Set<String>? projects,
    bool restoreTemplates = true,
  }) async {
    if (await file.length() > 200 * 1024 * 1024) {
      throw const FormatException('Backup exceeds 200 MB');
    }
    final data = jsonDecode(await file.readAsString()) as Json;
    if (data['format'] != 'the-list' || data['version'] != 1) {
      throw const FormatException('Unsupported backup format');
    }
    final ops = (data['operations'] as List)
        .map((o) => Map<String, dynamic>.from(o as Map))
        .where((o) => projects == null || projects.contains(o['project']))
        .toList();
    for (final op in ops) {
      requireEdit(op['project'] as String);
      Store.validate(op);
    }
    final combined = templates;
    if (restoreTemplates && data['templates'] is List) {
      for (final value in data['templates'] as List) {
        if (value is! Map ||
            value['name'] is! String ||
            value['columns'] is! String) {
          continue;
        }
        final template = <String, dynamic>{
          for (final key in ['name', 'description', 'label', 'columns', 'tags'])
            key: value[key] ?? '',
        };
        if (template.values.any((v) => v is! String || v.length > 50000) ||
            (template['name'] as String).trim().isEmpty) {
          throw const FormatException('Invalid template');
        }
        final id = uuid.v4();
        Store.validate({
          'id': id,
          'entity': id,
          'project': id,
          'device': device,
          'counter': 1,
          'kind': 'project',
          'fields': {'columns': template['columns']},
        });
        if (!combined.any((e) => jsonEncode(e) == jsonEncode(template))) {
          combined.add(template);
        }
      }
    }
    final referenced = ops
        .expand(
          (o) => ['photo', 'cover'].map((key) => (o['fields'] as Map)[key]),
        )
        .toSet();
    final photos = Map<String, dynamic>.from(data['photos'] as Map)
      ..removeWhere(
        (key, value) => projects != null && !referenced.contains(key),
      );
    for (final entry in photos.entries) {
      blob(entry.key);
      final bytes = base64Decode(entry.value as String);
      if (bytes.length > 20 * 1024 * 1024 ||
          sha256.convert(bytes).toString() != entry.key) {
        throw const FormatException('Photo integrity check failed');
      }
    }
    for (final entry in photos.entries) {
      final f = blob(entry.key);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(base64Decode(entry.value as String), flush: true);
    }
    apply(ops);
    if (restoreTemplates) {
      setSetting('templates', jsonEncode(combined));
      touch();
    }
  }
}
