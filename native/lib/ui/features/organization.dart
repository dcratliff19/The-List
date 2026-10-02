part of '../workspace.dart';

extension _WorkspaceFeaturesOrganization on _WorkspaceState {
  Future<void> tagManager() => featureSheet(
    'Manage tags',
    (ctx, update) => Column(
      children: [
        const Text(
          'Rename a tag, merge it into another tag, or leave the replacement blank to remove it. Changes apply across your workspace.',
        ),
        for (final tag in store.allTags)
          ListTile(
            title: Text(tag),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => act(() async {
              final result = await featureForm('Rename or merge tag', {
                'Replacement': tag,
              });
              if (result != null) store.renameTag(tag, result['Replacement']!);
            }),
          ),
      ],
    ),
  );
  Future<void> templatesDialog() => featureSheet(
    'Project templates',
    (ctx, update) => Column(
      children: [
        const Text(
          'Save a template from Project tools. Templates create an empty project with your chosen columns, category and tags.',
        ),
        for (final template in store.templates)
          ListTile(
            title: Text(template['name']),
            trailing: const Icon(Icons.add),
            onTap: () => act(() async {
              final result = await featureForm('Create from template', {
                'Project name': template['name'],
              });
              if (result != null && result['Project name']!.trim().isNotEmpty) {
                final id = store.createFromTemplate(
                  template,
                  result['Project name']!.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                openProject(id);
              }
            }),
          ),
      ],
    ),
  );
}
