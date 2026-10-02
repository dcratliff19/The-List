part of '../workspace.dart';

extension _WorkspaceNavigationView on _WorkspaceState {
  Widget sidebar() => Material(
    color: surface,
    child: Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: muted.withValues(alpha: .12))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 27, 20, 35),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 37,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.bookmark_outline_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'The List',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    '.',
                    style: TextStyle(
                      fontSize: 28,
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 20, 16),
              child: Text(
                'PERSONAL WORKSPACE',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
            ),
            nav(
              Icons.grid_view_rounded,
              'All projects',
              WorkspaceSection.projects,
              count: store.projects.where((e) => !e.flag('archived')).length,
            ),
            nav(
              Icons.notifications_none_rounded,
              'Reminders',
              WorkspaceSection.reminders,
              count: store.entries
                  .where(
                    (e) =>
                        e.kind == 'reminder' && !e.deleted && !e.flag('done'),
                  )
                  .length,
            ),
            nav(Icons.today_outlined, 'Today', WorkspaceSection.today),
            nav(
              Icons.inbox_outlined,
              'Inbox',
              WorkspaceSection.inbox,
              count: store.unreadComments,
            ),
            nav(
              Icons.dynamic_feed_outlined,
              'Feed',
              WorkspaceSection.feed,
              count: store.unreadActivity,
            ),
            nav(
              Icons.star_border_rounded,
              'Favorites',
              WorkspaceSection.favorites,
            ),
            ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('Quick capture'),
              onTap: () => act(() => capture()),
            ),
            const SizedBox(height: 25),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'YOUR PROJECTS',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.6,
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  iconAction(Icons.add, 'New project', () => editProject()),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                children: [
                  ...store.projects
                      .where((e) => !e.flag('archived'))
                      .map(
                        (e) => ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          selected: projectId == e.id,
                          selectedTileColor: accent.withValues(alpha: .07),
                          leading: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: Color(
                                int.tryParse(e.text('color')) ?? 0xffbcaa87,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          title: Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12),
                          ),
                          onTap: () => openProject(e.id),
                        ),
                      ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.add, size: 16, color: muted),
                    title: Text(
                      'New project',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    onTap: () => editProject(),
                  ),
                ],
              ),
            ),
            nav(Icons.people_outline, 'Join a project', null, action: sharing),
            nav(
              Icons.inventory_2_outlined,
              'Archive',
              WorkspaceSection.archive,
            ),
            nav(Icons.settings_outlined, 'Settings', null, action: settings),
            Container(
              margin: const EdgeInsets.fromLTRB(23, 20, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xff739580),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Your ideas, saved here.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Available offline on this device',
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: accent.withValues(alpha: .10),
                    child: Text(
                      'Y',
                      style: TextStyle(
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your workspace',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Personal & private',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget nav(
    IconData icon,
    String title,
    WorkspaceSection? destination, {
    int? count,
    VoidCallback? action,
  }) {
    final selected = section == destination && projectId == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
      child: ListTile(
        dense: true,
        minLeadingWidth: 20,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        selected: selected,
        selectedColor: accent,
        selectedTileColor: accent.withValues(alpha: .08),
        leading: Icon(icon, size: 19),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        trailing: count != null && count > 0
            ? Text('$count', style: TextStyle(fontSize: 11, color: muted))
            : null,
        onTap:
            action ??
            (destination == null ? null : () => navigate(destination)),
      ),
    );
  }

  Widget topbar(bool wide) => Container(
    height: 77,
    padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 10),
    decoration: BoxDecoration(
      color: surface,
      border: Border(bottom: BorderSide(color: muted.withValues(alpha: .1))),
    ),
    child: Row(
      children: [
        if (!wide)
          Builder(
            builder: (context) => iconAction(
              Icons.menu,
              'Open navigation',
              () => Scaffold.of(context).openDrawer(),
            ),
          ),
        if (wide) ...[
          Text('Workspace', style: TextStyle(fontSize: 11, color: muted)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.chevron_right, size: 14),
          ),
          Flexible(
            child: Text(
              project?.title ?? sectionTitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(),
        ],
        Expanded(
          flex: wide ? 0 : 1,
          child: SizedBox(
            width: wide ? 270 : null,
            child: TextField(
              controller: search,
              onChanged: (v) => rebuild(() => query = v),
              style: TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search your list',
                prefixIcon: Icon(Icons.search, size: 17),
                suffixIcon: query.isNotEmpty
                    ? iconAction(Icons.close, 'Clear search', () {
                        search.clear();
                        rebuild(() => query = '');
                      })
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
