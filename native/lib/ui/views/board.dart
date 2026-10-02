part of '../workspace.dart';

extension _WorkspaceBoardView on _WorkspaceState {
  Future<void> addExistingToBoard() async {
    String term = '';
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final available = store
              .items(projectId!)
              .where(
                (e) =>
                    e.kind != 'reminder' &&
                    !boardColumns.containsKey(e.text('boardStatus')) &&
                    ('${e.title} ${e.text('tags')}').toLowerCase().contains(
                      term.toLowerCase(),
                    ),
              )
              .toList();
          return AlertDialog(
            title: const Text('Add to board'),
            content: SizedBox(
              width: 440,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Find a project item',
                    ),
                    onChanged: (value) => update(() => term = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: available.isEmpty
                        ? const Center(
                            child: Text(
                              'No matching items to add. Create a new card instead.',
                            ),
                          )
                        : ListView(
                            children: available
                                .map(
                                  (entry) => ListTile(
                                    title: Text(entry.title),
                                    subtitle: Text(entry.kind),
                                    trailing: const Icon(Icons.add),
                                    onTap: () {
                                      moveCard(entry, boardColumns.keys.first);
                                      Navigator.pop(context);
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  Map<String, String> get boardColumns => store.columns(projectId!);
  String boardStatus(Entry entry) =>
      boardColumns.containsKey(entry.text('boardStatus'))
      ? entry.text('boardStatus')
      : 'todo';
  void moveCard(Entry entry, String status) {
    if (!allowEdit(entry.project)) return;
    final latest = store.get(entry.id);
    if (latest != null && !latest.deleted && latest.project == projectId) {
      store.update(latest, {
        'boardStatus': status,
        'rank': store.cards(latest.project, status).length,
      });
    }
  }

  Widget kanbanBoard(List<Entry> entries) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 850
          ? (constraints.maxWidth - 24) / 3
          : 280.0;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: boardColumns.entries.map((column) {
            final cards =
                entries.where((e) => boardStatus(e) == column.key).toList()
                  ..sort((a, b) {
                    final n = ((a.fields['rank'] as num?) ?? 0).compareTo(
                      (b.fields['rank'] as num?) ?? 0,
                    );
                    return n == 0 ? a.id.compareTo(b.id) : n;
                  });
            return Padding(
              padding: EdgeInsets.only(right: column.key == 'done' ? 0 : 12),
              child: DragTarget<String>(
                onWillAcceptWithDetails: (details) =>
                    entries.any((e) => e.id == details.data),
                onAcceptWithDetails: (details) =>
                    moveCard(store.get(details.data)!, column.key),
                builder: (context, candidates, rejected) => Container(
                  key: ValueKey('column-${column.key}'),
                  width: width,
                  constraints: const BoxConstraints(minHeight: 300),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withValues(
                      alpha: candidates.isEmpty ? .04 : .14,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: candidates.isEmpty
                          ? Theme.of(context).colorScheme.outlineVariant
                          : accent,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          '${column.value}  ${cards.length}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (cards.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Drop items here',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      for (final entry in cards)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: LongPressDraggable<String>(
                            data: entry.id,
                            maxSimultaneousDrags: store.canEdit(entry.project)
                                ? 1
                                : 0,
                            delay: const Duration(milliseconds: 180),
                            feedback: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: width - 24,
                                child: ListTile(title: Text(entry.title)),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: .35,
                              child: boardCard(entry),
                            ),
                            child: boardCard(entry),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    },
  );
  Widget boardCard(Entry entry) => Card(
    key: ValueKey('board-card-${entry.id}'),
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: () => detail(entry),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.kind.toUpperCase(),
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Move ${entry.title}',
                  onSelected: (status) {
                    if (!allowEdit(entry.project)) return;
                    if (status == '__up') {
                      store.reorderCard(entry, -1);
                    } else if (status == '__down') {
                      store.reorderCard(entry, 1);
                    } else {
                      moveCard(entry, status);
                    }
                  },
                  itemBuilder: (_) => [
                    ...boardColumns.entries.map(
                      (column) => PopupMenuItem(
                        value: column.key,
                        child: Text('Move to ${column.value}'),
                      ),
                    ),
                    const PopupMenuItem(value: '__up', child: Text('Move up')),
                    const PopupMenuItem(
                      value: '__down',
                      child: Text('Move down'),
                    ),
                    const PopupMenuItem(
                      value: '',
                      child: Text('Remove from board'),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              entry.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (entry.kind == 'link' && entry.priceLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  entry.priceLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if (entry.text('body').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  entry.text('body'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (entry.kind == 'link')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  domain(entry),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            if (entry.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: entry.tags.map(statusBadge).toList(),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
