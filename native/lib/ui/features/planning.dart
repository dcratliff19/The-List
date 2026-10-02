part of '../workspace.dart';

extension _WorkspaceFeaturesPlanning on _WorkspaceState {
  Future<void> projectTools() => featureSheet(
    'Project tools',
    (ctx, update) => Column(
      children: [
        ListTile(
          leading: const Icon(Icons.view_kanban_outlined),
          title: const Text('Manage board columns'),
          onTap: store.canEdit(projectId!) ? () => act(manageColumns) : null,
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Project budget'),
          onTap: store.canEdit(projectId!) ? () => act(editBudget) : null,
        ),
        ListTile(
          leading: const Icon(Icons.compare_arrows),
          title: const Text('Compare purchase options'),
          onTap: () => act(compareOptions),
        ),
        ListTile(
          leading: const Icon(Icons.copy_all),
          title: const Text('Save as template'),
          subtitle: const Text(
            'Structure and tags only; no items are added to future boards.',
          ),
          onTap: () => act(() async {
            final value = await featureForm('Save project template', {
              'Name': project!.title,
            });
            if (value != null) {
              store.saveTemplate(project!, value['Name']!);
              message('Template saved.');
            }
          }),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Activity and conflict review'),
          onTap: () => act(activity),
        ),
        ListTile(
          leading: const Icon(Icons.people_outline),
          title: const Text('People and connection status'),
          onTap: people,
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Export this project'),
          onTap: () => act(exportProject),
        ),
      ],
    ),
  );

  Future<void> manageColumns() => featureSheet(
    'Board columns',
    (ctx, update) => Column(
      children: [
        const Text(
          'Move or remove cards before deleting a column. Arrows change column order.',
        ),
        for (final column in store.columns(projectId!).entries)
          ListTile(
            title: Text(column.value),
            subtitle: Text(
              '${store.cards(projectId!, column.key).length} cards',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Move ${column.value} left',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => act(() async {
                    final entries = store.columns(projectId!).entries.toList();
                    final i = entries.indexWhere((c) => c.key == column.key);
                    if (i > 0) {
                      final c = entries.removeAt(i);
                      entries.insert(i - 1, c);
                      store.saveColumns(projectId!, Map.fromEntries(entries));
                    }
                  }),
                ),
                IconButton(
                  tooltip: 'Rename ${column.value}',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => act(() async {
                    final result = await featureForm('Rename column', {
                      'Name': column.value,
                    });
                    if (result != null) {
                      store.saveColumns(projectId!, {
                        ...store.columns(projectId!),
                        column.key: result['Name']!.trim(),
                      });
                    }
                  }),
                ),
                IconButton(
                  tooltip: 'Delete ${column.value}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => act(() async {
                    final columns = store.columns(projectId!)
                      ..remove(column.key);
                    store.saveColumns(projectId!, columns);
                  }),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => act(() async {
            final result = await featureForm('New column', {'Name': ''});
            if (result != null) {
              store.saveColumns(projectId!, {
                ...store.columns(projectId!),
                uuid.v4(): result['Name']!.trim(),
              });
            }
          }),
          icon: const Icon(Icons.add),
          label: const Text('Add column'),
        ),
      ],
    ),
  );

  Future<void> editBudget() async {
    final result = await featureForm(
      'Project budget',
      {
        'Budget': project!.text('budget'),
        'Currency': project!.text('budgetCurrency').isEmpty
            ? 'USD'
            : project!.text('budgetCurrency'),
      },
      choices: {'Currency': Entry.currencies},
      help:
          'Remaining budget uses links explicitly marked Chosen, Ordered or Received. Other currencies remain separate.',
    );
    if (result == null) return;
    final cents = Entry.parsePrice(result['Budget']!);
    store.update(project!, {
      'budget': cents == null ? '' : Entry.amount(cents),
      'budgetCurrency': result['Currency'],
    });
  }

  Widget budgetSummary() {
    final cents = Entry.parsePrice(project!.text('budget'));
    if (cents == null) return const SizedBox.shrink();
    final currency = project!.text('budgetCurrency');
    final chosen = store.plannedTotals(projectId!)[currency] ?? 0;
    final difference = cents - chosen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Budget $currency ${Entry.amount(cents)} · Planned ${Entry.amount(chosen)} · ${difference < 0 ? 'Over by' : 'Remaining'} ${Entry.amount(difference.abs())}',
        style: TextStyle(
          color: difference < 0 ? Theme.of(context).colorScheme.error : accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> compareOptions() => featureSheet('Purchase comparison', (
    ctx,
    update,
  ) {
    final groups =
        store
            .items(projectId!)
            .where((e) => e.kind == 'link')
            .map((e) => e.text('comparison'))
            .toSet()
            .toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Set a comparison group in an item’s planning options. Choosing one option returns the other members of its group to Considering.',
        ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              group.isEmpty ? 'Ungrouped' : group,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Item')),
                DataColumn(label: Text('Unit price')),
                DataColumn(label: Text('Qty')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Select')),
              ],
              rows: store
                  .items(projectId!)
                  .where(
                    (e) => e.kind == 'link' && e.text('comparison') == group,
                  )
                  .map(
                    (e) => DataRow(
                      cells: [
                        DataCell(
                          SizedBox(width: 160, child: Text(e.title)),
                          onTap: () => detail(e),
                        ),
                        DataCell(
                          Text(
                            e.priceLabel.isEmpty ? 'Unpriced' : e.priceLabel,
                          ),
                        ),
                        DataCell(Text('${e.quantity}')),
                        DataCell(
                          Text(
                            e.text('purchaseStatus').isEmpty
                                ? 'considering'
                                : e.text('purchaseStatus'),
                          ),
                        ),
                        DataCell(
                          TextButton(
                            onPressed: () => store.chooseAlternative(e),
                            child: const Text('Choose'),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  });

  Future<void> itemPlanning(
    Entry original,
  ) => featureSheet('Planning · ${original.title}', (ctx, update) {
    final e = store.get(original.id)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Assigned to'),
          subtitle: Text(
            e.text('assignee').isEmpty ? 'Unassigned' : e.text('assignee'),
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: !store.canEdit(e.project)
              ? null
              : () => act(() async {
                  final result = await featureForm('Assign item', {
                    'Name': e.text('assignee'),
                  });
                  if (result != null) {
                    store.update(e, {'assignee': result['Name']!.trim()});
                  }
                }),
        ),
        if (e.kind == 'link')
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Purchase options'),
            subtitle: Text(
              '${e.quantity} × ${e.priceLabel.isEmpty ? 'Unpriced' : e.priceLabel} · ${e.text('purchaseStatus').isEmpty ? 'considering' : e.text('purchaseStatus')}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: !store.canEdit(e.project)
                ? null
                : () => act(() async {
                    final result = await featureForm(
                      'Purchase options',
                      {
                        'Quantity': '${e.quantity}',
                        'Status': e.text('purchaseStatus').isEmpty
                            ? 'considering'
                            : e.text('purchaseStatus'),
                        'Comparison group': e.text('comparison'),
                      },
                      choices: {
                        'Status': [
                          'considering',
                          'chosen',
                          'ordered',
                          'received',
                        ],
                      },
                    );
                    if (result != null) {
                      final quantity = int.tryParse(result['Quantity']!);
                      if (quantity == null ||
                          quantity < 1 ||
                          quantity > 1000000) {
                        throw const FormatException(
                          'Enter a whole quantity from 1 to 1,000,000.',
                        );
                      }
                      store.update(e, {
                        'quantity': quantity,
                        'purchaseStatus': result['Status'],
                        'comparison': result['Comparison group']!.trim(),
                      });
                    }
                  }),
          ),
        const Divider(),
        const Text('Checklist', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final task in store.childrenOf(e.id, 'check'))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(task.title),
            value: task.flag('done'),
            onChanged: !store.canEdit(e.project)
                ? null
                : (v) => store.update(task, {'done': v}),
            secondary: IconButton(
              tooltip: 'Remove checklist item',
              icon: const Icon(Icons.close),
              onPressed: !store.canEdit(e.project)
                  ? null
                  : () => store.update(task, {'deleted': true}),
            ),
          ),
        TextButton.icon(
          onPressed: !store.canEdit(e.project)
              ? null
              : () => act(() async {
                  final result = await featureForm('Add checklist item', {
                    'Title': '',
                  });
                  if (result != null && result['Title']!.trim().isNotEmpty) {
                    store.create('check', e.project, {
                      'title': result['Title']!.trim(),
                      'target': e.id,
                      'done': false,
                    });
                  }
                }),
          icon: const Icon(Icons.add),
          label: const Text('Add checklist item'),
        ),
        const Divider(),
        commentThread(e),
      ],
    );
  });
}
