part of '../workspace.dart';

extension _WorkspaceFeaturesComments on _WorkspaceState {
  Future<void> comments(Entry target) => featureSheet(
    'Comments · ${target.title}',
    (ctx, update) => commentThread(target),
  );

  Widget commentThread(Entry target) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Comments', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text(
        'Shared participants receive comments in their Inbox when updates sync.',
      ),
      if (store.childrenOf(target.id, 'comment').isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Start the conversation.'),
        ),
      for (final comment in store.childrenOf(target.id, 'comment'))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: SelectableText(comment.text('body')),
          subtitle: Text(
            '${comment.text('author')} · ${DateTime.tryParse(comment.text('created'))?.toLocal().toString().substring(0, 16) ?? ''}',
          ),
        ),
      TextButton.icon(
        onPressed: !store.canEdit(target.project)
            ? null
            : () => act(() async {
                final result = await featureForm('Add comment', {
                  'Comment': '',
                });
                if (result != null && result['Comment']!.trim().isNotEmpty) {
                  store.addComment(target, result['Comment']!);
                }
              }),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Add comment'),
      ),
    ],
  );
}
