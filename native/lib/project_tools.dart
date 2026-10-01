part of 'store.dart';

/// Project planning and capture operations built on the store's mutation rules.
extension ProjectTools on Store {
  String addComment(Entry target, String body) {
    final current = get(target.id);
    if (current == null ||
        current.deleted ||
        !['project', 'link', 'note', 'photo'].contains(current.kind)) {
      throw const FormatException(
        'Choose a project or list item to comment on.',
      );
    }
    if (body.trim().isEmpty) {
      throw const FormatException('Write a comment first.');
    }
    return create('comment', current.project, {
      'title': 'Comment',
      'body': body.trim(),
      'target': current.id,
    });
  }

  List<Entry> get commentInbox => db
      .select(
        'SELECT entities.* FROM comment_inbox JOIN entities ON entities.id=comment_inbox.comment ORDER BY comment_inbox.received DESC,comment_inbox.comment',
      )
      .map(_entry)
      .where((e) {
        final project = get(e.project), target = get(e.text('target'));
        return !e.deleted &&
            project != null &&
            !project.deleted &&
            target != null &&
            !target.deleted &&
            target.project == e.project;
      })
      .toList();
  bool commentUnread(String id) => db
      .select('SELECT seen FROM comment_inbox WHERE comment=?', [id])
      .any((r) => r['seen'] == 0);
  int get unreadComments =>
      commentInbox.where((e) => commentUnread(e.id)).length;
  void markCommentRead(String id, {bool read = true}) {
    db.execute('UPDATE comment_inbox SET seen=? WHERE comment=?', [
      read ? 1 : 0,
      id,
    ]);
    touch();
  }

  static const defaultColumns = {
    'todo': 'To do',
    'doing': 'In progress',
    'done': 'Done',
  };
  Map<String, String> columns(String pid) {
    final raw = get(pid)?.text('columns') ?? '';
    if (raw.isEmpty) return Map.of(defaultColumns);
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  void saveColumns(String pid, Map<String, String> next) {
    if (next.isEmpty ||
        next.length > 20 ||
        next.values.any((v) => v.trim().isEmpty || v.length > 60)) {
      throw const FormatException('Use 1–20 named columns.');
    }
    for (final item in items(pid)) {
      if (item.text('boardStatus').isNotEmpty &&
          !next.containsKey(item.text('boardStatus'))) {
        throw const FormatException(
          'Move or remove the cards in a column before deleting it.',
        );
      }
    }
    update(get(pid)!, {'columns': jsonEncode(next)});
  }

  List<Entry> cards(String pid, String column) =>
      items(pid)
          .where(
            (e) =>
                e.text('boardStatus') == column &&
                ['link', 'note', 'photo'].contains(e.kind),
          )
          .toList()
        ..sort((a, b) {
          final n = ((a.fields['rank'] as num?) ?? 0).compareTo(
            (b.fields['rank'] as num?) ?? 0,
          );
          return n == 0 ? a.id.compareTo(b.id) : n;
        });
  void reorderCard(Entry item, int delta) {
    final list = cards(item.project, item.text('boardStatus'));
    final at = list.indexWhere((e) => e.id == item.id);
    final next = at + delta;
    if (at < 0 || next < 0 || next >= list.length) return;
    list.removeAt(at);
    list.insert(next, item);
    for (var i = 0; i < list.length; i++) {
      update(list[i], {'rank': i});
    }
  }

  List<String> get allTags =>
      entries.where((e) => !e.deleted).expand((e) => e.tags).toSet().toList()
        ..sort();
  void renameTag(String old, String replacement) {
    final newTags = Entry.parseTags(replacement);
    for (final e in entries.where(
      (e) =>
          !e.deleted &&
          canEdit(e.project) &&
          e.tags.any((t) => t.toLowerCase() == old.toLowerCase()),
    )) {
      update(e, {
        'tags': Entry.parseTags(
          e.tags
              .expand(
                (t) => t.toLowerCase() == old.toLowerCase() ? newTags : [t],
              )
              .join(' '),
        ).join(' '),
      });
    }
  }

  static String normalizedUrl(String value) {
    final uri = Uri.parse(value.trim());
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Use a full http:// or https:// address.');
    }
    // Repeated values are meaningful (for example, multiple product filters).
    // Sort keys for duplicate detection without collapsing their value lists.
    final params = Map<String, List<String>>.from(uri.queryParametersAll)
      ..removeWhere(
        (k, v) =>
            k.toLowerCase().startsWith('utm_') ||
            ['fbclid', 'gclid'].contains(k.toLowerCase()),
      );
    final sorted = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return uri
        .replace(
          host: uri.host.toLowerCase(),
          fragment: '',
          path: uri.path == '/' ? '' : uri.path,
          query: sorted.isEmpty ? '' : Uri(queryParameters: sorted).query,
        )
        .toString()
        .replaceAll(RegExp(r'[?#]+$'), '');
  }

  Entry? duplicate(String pid, String url) {
    final normalized = normalizedUrl(url);
    for (final e in items(pid).where((e) => e.kind == 'link')) {
      try {
        if (normalizedUrl(e.text('url')) == normalized) return e;
      } catch (_) {
        /* Invalid legacy links do not block capture. */
      }
    }
    return null;
  }

  String inbox() {
    final existing = entries.where(
      (e) => e.kind == 'project' && e.flag('inbox') && !e.deleted,
    );
    return existing.isEmpty
        ? create('project', '', {'title': 'Inbox', 'inbox': true})
        : existing.first.id;
  }

  String moveFromInbox(Entry item, String destination) {
    requireEdit(destination);
    if (!(get(item.project)?.flag('inbox') ?? false) ||
        get(destination)?.kind != 'project') {
      throw const FormatException('Choose an inbox item and a project.');
    }
    if (item.kind == 'link' &&
        duplicate(destination, item.text('url')) != null) {
      throw const FormatException(
        'This link is already saved in that project.',
      );
    }
    final id = create(item.kind, destination, {
      ...item.fields,
      'boardStatus': '',
      'deleted': false,
    });
    for (final child in items(
      item.project,
    ).where((e) => e.text('target') == item.id)) {
      create(child.kind, destination, {
        ...child.fields,
        'target': id,
        'boardStatus': '',
        'deleted': false,
      });
      update(child, {'deleted': true});
    }
    update(item, {'deleted': true});
    return id;
  }

  Map<String, int> plannedTotals(String pid) {
    final totals = <String, int>{};
    for (final e in items(pid).where(
      (e) =>
          e.kind == 'link' &&
          ['chosen', 'ordered', 'received'].contains(e.text('purchaseStatus')),
    )) {
      if (e.priceMinor != null) {
        totals.update(
          e.currency,
          (n) => n + e.priceMinor! * e.quantity,
          ifAbsent: () => e.priceMinor! * e.quantity,
        );
      }
    }
    return totals;
  }

  void chooseAlternative(Entry selected) {
    final group = selected.text('comparison');
    if (group.isNotEmpty) {
      for (final e in items(selected.project).where(
        (e) =>
            e.kind == 'link' &&
            e.id != selected.id &&
            e.text('comparison') == group,
      )) {
        update(e, {'purchaseStatus': 'considering'});
      }
    }
    update(selected, {'purchaseStatus': 'chosen'});
  }

  List<Json> get templates => (jsonDecode(setting('templates') ?? '[]') as List)
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  void saveTemplate(Entry project, String name) {
    if (name.trim().isEmpty) throw const FormatException('Name the template.');
    final current = templates;
    current.add({
      'name': name.trim(),
      'description': project.text('description'),
      'label': project.text('label'),
      'columns': jsonEncode(columns(project.id)),
      'tags': items(project.id).expand((e) => e.tags).toSet().join(' '),
    });
    setSetting('templates', jsonEncode(current));
    touch();
  }

  String createFromTemplate(Json template, String title) =>
      create('project', '', {
        'title': title,
        'description': template['description'] ?? '',
        'label': template['label'] ?? '',
        'columns': template['columns'] ?? '',
        'tags': template['tags'] ?? '',
      });
  List<Entry> childrenOf(String target, String kind) =>
      entries
          .where(
            (e) => e.kind == kind && e.text('target') == target && !e.deleted,
          )
          .toList()
        ..sort((a, b) => a.text('created').compareTo(b.text('created')));
  void completeReminder(Entry reminder, bool done) {
    final repeat = reminder.text('repeat');
    if (!done || repeat.isEmpty || repeat == 'none') {
      update(reminder, {'done': done});
      return;
    }
    var due = DateTime.parse(reminder.text('due')).toLocal();
    final now = DateTime.now();
    for (var i = 0; i < 40000; i++) {
      if (repeat == 'monthly') {
        final day = (reminder.fields['repeatDay'] as int?) ?? due.day;
        final last = DateTime(due.year, due.month + 2, 0).day;
        due = DateTime(
          due.year,
          due.month + 1,
          day.clamp(1, last),
          due.hour,
          due.minute,
        );
      } else {
        due = DateTime(
          due.year,
          due.month,
          due.day + (repeat == 'weekly' ? 7 : 1),
          due.hour,
          due.minute,
        );
        if (repeat.startsWith('days:')) {
          final days = repeat.substring(5).split(',');
          if (!days.contains('${due.weekday}')) continue;
        }
      }
      if (due.isAfter(now)) break;
    }
    update(reminder, {
      'done': false,
      'due': due.toUtc().toIso8601String(),
      'lastCompleted': now.toUtc().toIso8601String(),
      'repeatDay':
          reminder.fields['repeatDay'] ??
          DateTime.parse(reminder.text('due')).toLocal().day,
    });
  }

  Future<Json> previewBackup(File file) async {
    if (await file.length() > 200 * 1024 * 1024) {
      throw const FormatException('Backup exceeds 200 MB');
    }
    final data = jsonDecode(await file.readAsString()) as Json;
    if (data['format'] != 'the-list' || data['version'] != 1) {
      throw const FormatException('Unsupported backup.');
    }
    final preview = Store(
      Directory.systemTemp,
      database: sqlite3.openInMemory(),
    );
    try {
      preview.apply(
        (data['operations'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
      return {
        'projects': preview.entries
            .where((e) => e.kind == 'project' && !e.deleted)
            .map((e) => e.toJson())
            .toList(),
        'counts': {
          for (final project in preview.entries.where(
            (e) => e.kind == 'project' && !e.deleted,
          ))
            project.id: preview.items(project.id).length,
        },
      };
    } finally {
      preview.dispose();
    }
  }
}
