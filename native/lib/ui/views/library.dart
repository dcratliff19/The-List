part of '../workspace.dart';

extension _WorkspaceLibraryView on _WorkspaceState {
  Widget body(bool wide) {
    final heading =
        project?.title ??
        (section == WorkspaceSection.projects
            ? 'Room for your next idea.'
            : sectionTitle);
    final sub =
        project?.text('description') ??
        switch (section) {
          WorkspaceSection.reminders =>
            'A little nudge, at just the right time.',
          WorkspaceSection.favorites => 'The things you keep coming back to.',
          WorkspaceSection.archive => 'Out of the way. Never out of reach.',
          _ =>
            'Keep the links, notes, and little discoveries that move your projects forward.',
        };
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        wide ? 42 : 20,
        wide ? 39 : 25,
        wide ? 42 : 20,
        25,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 16, height: 2, color: accent),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  'A LITTLE ORDER. A LOT OF POSSIBILITY.',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.7,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          LayoutBuilder(
            builder: (context, s) => Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 20,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: wide ? (s.maxWidth - 185).clamp(200, 700) : s.maxWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: TextStyle(
                          fontSize: wide ? 33 : 27,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.2,
                          height: 1.2,
                        ),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          sub,
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (![
                      WorkspaceSection.archive,
                      WorkspaceSection.feed,
                    ].contains(section) &&
                    (projectId == null || store.canEdit(projectId!)))
                  addButton(
                    projectId != null
                        ? 'Add to list'
                        : section == WorkspaceSection.inbox
                        ? 'Quick capture'
                        : [
                            WorkspaceSection.reminders,
                            WorkspaceSection.today,
                          ].contains(section)
                        ? 'New reminder'
                        : 'New project',
                    () => projectId != null
                        ? editItem()
                        : section == WorkspaceSection.inbox
                        ? act(() => capture())
                        : [
                            WorkspaceSection.reminders,
                            WorkspaceSection.today,
                          ].contains(section)
                        ? editReminder()
                        : editProject(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          if (overdue.isNotEmpty &&
              ![
                WorkspaceSection.reminders,
                WorkspaceSection.today,
              ].contains(section))
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(
                  '${overdue.length} reminder${overdue.length == 1 ? '' : 's'} need attention',
                ),
                subtitle: const Text(
                  'Missed a notification? Reminders stay here until you mark them done.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => navigate(WorkspaceSection.reminders),
              ),
            ),
          if (section == WorkspaceSection.feed)
            feedContent()
          else if (section == WorkspaceSection.inbox)
            inboxContent()
          else if (section == WorkspaceSection.today)
            todayContent()
          else if (project != null)
            projectContent(wide)
          else if (section == WorkspaceSection.reminders)
            reminderContent()
          else if (section == WorkspaceSection.favorites)
            itemsView(
              store.entries
                  .where(
                    (e) =>
                        !e.deleted &&
                        ['link', 'note', 'photo'].contains(e.kind) &&
                        e.flag('favorite'),
                  )
                  .toList(),
              wide,
            )
          else if (query.trim().isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                projectLibrary(wide),
                const SizedBox(height: 20),
                const Text('Matching links, notes and photos'),
                const SizedBox(height: 12),
                itemsView(
                  store.entries
                      .where(
                        (e) =>
                            !e.deleted &&
                            ['link', 'note', 'photo'].contains(e.kind) &&
                            store.get(e.project)?.flag('archived') ==
                                (section == WorkspaceSection.archive),
                      )
                      .toList(),
                  wide,
                ),
              ],
            )
          else
            projectLibrary(wide),
          const SizedBox(height: 40),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 50,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.offline_pin_outlined, size: 13, color: muted),
                  const SizedBox(width: 7),
                  Text(
                    'Offline by design. Yours by default.',
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                ],
              ),
              Text(
                'THE LIST / YOUR NEXT CHAPTER',
                style: TextStyle(fontSize: 8, letterSpacing: 1.5, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget projectLibrary(bool wide) {
    final list = store.projects
        .where(
          (e) =>
              e.flag('archived') == (section == WorkspaceSection.archive) &&
              matches(e),
        )
        .toList();
    if (list.isEmpty) {
      return empty(
        section == WorkspaceSection.archive
            ? 'A little breathing room.'
            : 'Good things start with a project.',
        section == WorkspaceSection.archive
            ? 'Archived projects will be kept here.'
            : 'A new home, a big trip, your next creative idea.\nGive it a place, then start collecting.',
        Icons.folder_open_rounded,
        action: section == WorkspaceSection.projects
            ? () => editProject()
            : null,
        example: section == WorkspaceSection.projects && store.projects.isEmpty,
      );
    }
    return LayoutBuilder(
      builder: (context, s) => Wrap(
        spacing: 20,
        runSpacing: 20,
        children: list
            .map(
              (e) => SizedBox(
                width: wide ? (s.maxWidth - 20) / 2 : s.maxWidth,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  elevation: 0,
                  color: surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: muted.withValues(alpha: .13)),
                  ),
                  child: InkWell(
                    onTap: () => openProject(e.id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 118,
                          width: double.infinity,
                          color: Color(
                            int.tryParse(e.text('color')) ?? 0xffb4a7d6,
                          ).withValues(alpha: .22),
                          child:
                              e.text('cover').isNotEmpty &&
                                  store.blob(e.text('cover')).existsSync()
                              ? Image.file(
                                  store.blob(e.text('cover')),
                                  fit: BoxFit.cover,
                                )
                              : Center(
                                  child: Icon(
                                    Icons.folder_outlined,
                                    size: 40,
                                    color: Color(
                                      int.tryParse(e.text('color')) ??
                                          0xff8a79b5,
                                    ),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(23),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.title,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Text(
                                '${store.items(e.id).where((x) => ['link', 'note', 'photo'].contains(x.kind)).length} things collected',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget empty(
    String title,
    String subtitle,
    IconData icon, {
    VoidCallback? action,
    bool example = false,
  }) => EmptyWorkspace(
    title: title,
    subtitle: subtitle,
    icon: icon,
    action: action,
    onExample: example ? loadExample : null,
  );
}
