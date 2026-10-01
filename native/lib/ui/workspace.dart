import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../store.dart';
import '../services/media.dart';
import '../services/sync.dart';
import '../services/sharing_config.dart';
import '../services/reminders.dart';
import '../services/excel_backup.dart';
import '../services/project_pdf.dart';
part 'actions.dart';
part 'features.dart';
part 'feed.dart';

/// Keeps editor controllers alive through the dialog's closing animation.
/// A popped route can still build until [DialogRoute.completed] resolves.
Future<T?> _showEditorDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required List<TextEditingController> controllers,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  try {
    final result = await navigator.push(route);
    await route.completed;
    return result;
  } finally {
    for (final controller in controllers) {
      controller.dispose();
    }
  }
}

class Workspace extends StatefulWidget {
  final Store store;
  final VoidCallback onTheme;
  final bool servicesEnabled;
  final String? initialTarget;
  const Workspace({
    super.key,
    required this.store,
    required this.onTheme,
    this.servicesEnabled = true,
    this.initialTarget,
  });
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  Store get store => widget.store;
  String section = 'projects', filter = 'all', query = '';
  String? projectId;
  final search = TextEditingController();
  Timer? reminderClock;
  StreamSubscription<Uri>? captureSubscription;
  final captureChannel = const MethodChannel('thelist/capture');
  final pendingCaptures = <String>[];
  bool captureOpen = false;
  Future<void> receiveCapture(String text) async {
    if (text.isEmpty || text.length > 32000) return;
    pendingCaptures.add(text);
    if (captureOpen) return;
    captureOpen = true;
    while (mounted && pendingCaptures.isNotEmpty) {
      final value = pendingCaptures.removeAt(0);
      final urls = RegExp(
        r'https?://[^\s]+',
      ).allMatches(value).map((m) => m.group(0)!).join('\n');
      await act(
        () => capture(
          initial: urls.isEmpty ? '' : urls,
          note: value.replaceAll(RegExp(r'https?://[^\s]+'), '').trim(),
        ),
      );
    }
    captureOpen = false;
  }

  void receiveUri(Uri uri) {
    if (uri.scheme == 'thelist-capture' && uri.host == 'save') {
      receiveCapture(uri.queryParameters['url'] ?? '');
    }
  }

  List<Entry> get overdue => store.entries
      .where(
        (e) =>
            e.kind == 'reminder' &&
            !e.deleted &&
            !e.flag('done') &&
            (DateTime.tryParse(e.text('due'))?.isBefore(DateTime.now()) ??
                false),
      )
      .toList();
  late final media = MediaService(store);
  late final sync = SyncService(store);
  late final reminders = ReminderService(store);
  late final excelBackup = ExcelBackup(store);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reminderClock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        reminders.opened.value = widget.initialTarget;
        if (!widget.servicesEnabled) openNotification();
      });
    }
    if (widget.servicesEnabled) {
      final links = AppLinks();
      captureSubscription = links.uriLinkStream.listen(
        receiveUri,
        onError: (Object error) =>
            message('Could not read shared link: $error'),
      );
      if (Platform.isAndroid) {
        captureChannel.setMethodCallHandler((call) async {
          if (call.method == 'capture' && call.arguments is String) {
            receiveCapture(call.arguments as String);
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final initial = await captureChannel.invokeMethod<String>(
            'getInitialText',
          );
          if (initial != null && mounted) receiveCapture(initial);
        });
      }
      if (Platform.isIOS) {
        WidgetsBinding.instance.addPostFrameCallback((_) => readAppleShares());
      }
      excelBackup.initialize();
      sync.initialize();
      media.repairMissing();
      reminders.initialize();
      reminders.opened.addListener(openNotification);
    }
  }

  Future<void> readAppleShares() async {
    try {
      final shares =
          await captureChannel.invokeListMethod<String>('getPendingShares') ??
          [];
      for (final share in shares) {
        if (mounted) receiveCapture(share);
      }
    } catch (error) {
      message('Shared links could not be read: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.servicesEnabled &&
        Platform.isIOS &&
        state == AppLifecycleState.resumed) {
      readAppleShares();
    }
  }

  void openNotification() {
    final id = reminders.opened.value;
    final target = id == null ? null : store.get(id);
    if (target != null) {
      if (target.kind == 'project') {
        openProject(target.id);
      } else {
        openProject(target.project);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) detail(target);
        });
      }
    }
  }

  Color get accent => Theme.of(context).colorScheme.primary;
  Color get muted => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get surface => Theme.of(context).colorScheme.surface;
  Entry? get project => projectId == null ? null : store.get(projectId!);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    reminderClock?.cancel();
    captureSubscription?.cancel();
    if (widget.servicesEnabled && Platform.isAndroid) {
      captureChannel.setMethodCallHandler(null);
    }
    search.dispose();
    sync.dispose();
    reminders.opened.removeListener(openNotification);
    reminders.dispose();
    excelBackup.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> act(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      message(e.toString());
    }
  }

  void navigate(String next) => setState(() {
    section = next;
    projectId = null;
    filter = 'all';
    query = '';
    search.clear();
  });
  void openProject(String id) => setState(() {
    projectId = id;
    section = 'projects';
    filter = 'all';
    query = '';
    search.clear();
  });
  Widget ib(IconData icon, String label, VoidCallback action) =>
      IconButton(tooltip: label, onPressed: action, icon: Icon(icon, size: 19));
  Widget primary(String label, VoidCallback action) => FilledButton.icon(
    onPressed: action,
    icon: Icon(Icons.add, size: 17),
    label: Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
  );
  Widget pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: accent,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  bool matches(Entry e) {
    final content = [
      e.title,
      e.text('body'),
      e.text('url'),
      e.tags.join(' '),
      e.text('description'),
    ].join(' ').toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .every(
          (term) => term.startsWith('#')
              ? e.tags.any(
                  (tag) => tag.toLowerCase().contains(term.substring(1)),
                )
              : content.contains(term),
        );
  }

  String domain(Entry e) =>
      Uri.tryParse(e.text('url'))?.host.replaceFirst('www.', '') ?? 'Web link';
  String get sectionTitle => switch (section) {
    'today' => 'Today',
    'inbox' => 'Inbox',
    'feed' => 'Shared activity',
    'reminders' => 'Reminders',
    'favorites' => 'Favorites',
    'archive' => 'Archive',
    _ => 'All projects',
  };
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, s) {
        final wide = s.maxWidth >= 850;
        return Scaffold(
          drawer: wide ? null : Drawer(child: sidebar()),
          body: Row(
            children: [
              if (wide) SizedBox(width: 238, child: sidebar()),
              Expanded(
                child: Column(
                  children: [
                    SafeArea(bottom: false, child: topbar(wide)),
                    Expanded(child: body(wide)),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: [
                    'projects',
                    'today',
                    'inbox',
                    'reminders',
                    'feed',
                  ].indexOf(section).clamp(0, 4),
                  onDestinationSelected: (i) => navigate(
                    ['projects', 'today', 'inbox', 'reminders', 'feed'][i],
                  ),
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_rounded),
                      label: 'Projects',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.today_outlined),
                      label: 'Today',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: store.unreadComments > 0,
                        label: Text('${store.unreadComments}'),
                        child: const Icon(Icons.inbox_outlined),
                      ),
                      label: 'Inbox',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.notifications_none),
                      label: 'Reminders',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.dynamic_feed_outlined),
                      label: 'Feed',
                    ),
                  ],
                ),
        );
      },
    ),
  );
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
              'projects',
              count: store.projects.where((e) => !e.flag('archived')).length,
            ),
            nav(
              Icons.notifications_none_rounded,
              'Reminders',
              'reminders',
              count: store.entries
                  .where(
                    (e) =>
                        e.kind == 'reminder' && !e.deleted && !e.flag('done'),
                  )
                  .length,
            ),
            nav(Icons.today_outlined, 'Today', 'today'),
            nav(
              Icons.inbox_outlined,
              'Inbox',
              'inbox',
              count: store.unreadComments,
            ),
            nav(
              Icons.dynamic_feed_outlined,
              'Feed',
              'feed',
              count: store.unreadActivity,
            ),
            nav(Icons.star_border_rounded, 'Favorites', 'favorites'),
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
                  ib(Icons.add, 'New project', () => editProject()),
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
            nav(
              Icons.people_outline,
              'Join a project',
              'sharing',
              action: sharing,
            ),
            nav(Icons.inventory_2_outlined, 'Archive', 'archive'),
            nav(
              Icons.settings_outlined,
              'Settings',
              'settings',
              action: settings,
            ),
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
    String key, {
    int? count,
    VoidCallback? action,
  }) {
    final selected = section == key && projectId == null;
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
        onTap: action ?? () => navigate(key),
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
            builder: (context) => ib(
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
              onChanged: (v) => setState(() => query = v),
              style: TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search your list',
                prefixIcon: Icon(Icons.search, size: 17),
                suffixIcon: query.isNotEmpty
                    ? ib(Icons.close, 'Clear search', () {
                        search.clear();
                        setState(() => query = '');
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
  Widget body(bool wide) {
    final heading =
        project?.title ??
        (section == 'projects' ? 'Room for your next idea.' : sectionTitle);
    final sub =
        project?.text('description') ??
        switch (section) {
          'reminders' => 'A little nudge, at just the right time.',
          'favorites' => 'The things you keep coming back to.',
          'archive' => 'Out of the way. Never out of reach.',
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
                if (!['archive', 'feed'].contains(section) &&
                    (projectId == null || store.canEdit(projectId!)))
                  primary(
                    projectId != null
                        ? 'Add to list'
                        : section == 'inbox'
                        ? 'Quick capture'
                        : ['reminders', 'today'].contains(section)
                        ? 'New reminder'
                        : 'New project',
                    () => projectId != null
                        ? editItem()
                        : section == 'inbox'
                        ? act(() => capture())
                        : ['reminders', 'today'].contains(section)
                        ? editReminder()
                        : editProject(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          if (overdue.isNotEmpty && !['reminders', 'today'].contains(section))
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
                onTap: () => navigate('reminders'),
              ),
            ),
          if (section == 'feed')
            feedContent()
          else if (section == 'inbox')
            inboxContent()
          else if (section == 'today')
            todayContent()
          else if (project != null)
            projectContent(wide)
          else if (section == 'reminders')
            reminderContent()
          else if (section == 'favorites')
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
                                (section == 'archive'),
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
          (e) => e.flag('archived') == (section == 'archive') && matches(e),
        )
        .toList();
    if (list.isEmpty) {
      return empty(
        section == 'archive'
            ? 'A little breathing room.'
            : 'Good things start with a project.',
        section == 'archive'
            ? 'Archived projects will be kept here.'
            : 'A new home, a big trip, your next creative idea.\nGive it a place, then start collecting.',
        Icons.folder_open_rounded,
        action: section == 'projects' ? () => editProject() : null,
        example: section == 'projects' && store.projects.isEmpty,
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
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 20),
    decoration: BoxDecoration(
      border: Border.all(color: muted.withValues(alpha: .12)),
      borderRadius: BorderRadius.circular(15),
      color: surface.withValues(alpha: .5),
    ),
    child: Column(
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(icon, size: 35, color: accent),
        ),
        const SizedBox(height: 25),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 13),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: muted, height: 1.8),
        ),
        const SizedBox(height: 23),
        if (action != null) primary('Create your first project', action),
        if (example)
          TextButton(
            onPressed: loadExample,
            child: const Text(
              'Explore an example project',
              style: TextStyle(fontSize: 11),
            ),
          ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 25,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            feature(Icons.link, 'Links with context'),
            feature(Icons.notes, 'Notes worth keeping'),
            feature(Icons.notifications_none, 'A nudge at the right time'),
          ],
        ),
      ],
    ),
  );
  Widget feature(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: muted),
      const SizedBox(width: 7),
      Text(text, style: TextStyle(fontSize: 10, color: muted)),
    ],
  );
  bool get boardView => store.setting('view-$projectId') == 'board';
  Widget projectContent(bool wide) {
    final all = store
        .items(projectId!)
        .where((e) => ['link', 'note', 'photo'].contains(e.kind))
        .toList();
    return Column(
      children: [
        if (!store.canEdit(projectId!))
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Read-only project'),
              subtitle: Text(
                'You can browse and set personal reminders. Ask the owner for update access to make changes.',
              ),
            ),
          ),
        Row(
          children: [
            pill(
              project!.text('label').isEmpty
                  ? 'PROJECT'
                  : project!.text('label'),
            ),
            const SizedBox(width: 12),
            Text(
              '${all.length} things collected',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: sharing,
              icon: Icon(Icons.people_outline, size: 17),
              label: const Text('Share', style: TextStyle(fontSize: 11)),
            ),
            PopupMenuButton<String>(
              tooltip: 'Project options',
              onSelected: (v) {
                if (v != 'remind' && !allowEdit(projectId!)) return;
                if (v == 'edit') editProject(project);
                if (v == 'cover') pickCover();
                if (v == 'remind') editReminder(target: project);
                if (v == 'archive') {
                  store.update(project!, {
                    'archived': !project!.flag('archived'),
                  });
                  navigate('projects');
                }
                if (v == 'delete') remove(project!);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit project')),
                const PopupMenuItem(
                  value: 'cover',
                  child: Text('Attach cover photo'),
                ),
                const PopupMenuItem(
                  value: 'remind',
                  child: Text('Set a reminder'),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    project!.flag('archived')
                        ? 'Restore project'
                        : 'Archive project',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Move to trash'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => act(projectTools),
              icon: const Icon(Icons.tune),
              label: const Text('Project tools'),
            ),
            OutlinedButton.icon(
              onPressed: () => comments(project!),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Project comments'),
            ),
            OutlinedButton.icon(
              onPressed: store.canEdit(projectId!)
                  ? () => act(() => capture())
                  : null,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Import links'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        budgetSummary(),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              store.projectTotals(projectId!).isEmpty
                  ? 'Project total: no prices added'
                  : 'Project total: ${store.projectTotals(projectId!).entries.map((total) => '${total.key} ${Entry.amount(total.value)}').join('  ·  ')}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('List'),
                icon: Icon(Icons.view_list_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Board'),
                icon: Icon(Icons.view_kanban_outlined),
              ),
            ],
            selected: {boardView},
            onSelectionChanged: (selection) => setState(() {
              store.setSetting(
                'view-$projectId',
                selection.first ? 'board' : 'list',
              );
            }),
          ),
        ),
        const SizedBox(height: 18),
        const Divider(height: 1),
        SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in ['all', 'link', 'note', 'photo'])
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: TextButton(
                            onPressed: () => setState(() => filter = f),
                            style: TextButton.styleFrom(
                              foregroundColor: filter == f ? accent : muted,
                            ),
                            child: Text(
                              {
                                'all': 'Everything  ${all.length}',
                                'link': 'Links',
                                'note': 'Notes',
                                'photo': 'Photos',
                              }[f]!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: filter == f
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (wide)
                Text(
                  'Recently added',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
            ],
          ),
        ),
        if (boardView) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: store.canEdit(projectId!)
                      ? addExistingToBoard
                      : null,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Add existing item'),
                ),
                FilledButton.icon(
                  onPressed: store.canEdit(projectId!)
                      ? () => editItem(null, true)
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('New card'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Choose items for this board. Other project items stay in your List.',
            ),
          ),
        ],
        if (boardView)
          kanbanBoard(
            all
                .where(
                  (e) =>
                      boardColumns.containsKey(e.text('boardStatus')) &&
                      (filter == 'all' || e.kind == filter) &&
                      matches(e),
                )
                .toList(),
          )
        else
          itemsView(
            all
                .where(
                  (e) => (filter == 'all' || e.kind == filter) && matches(e),
                )
                .toList(),
            wide,
          ),
      ],
    );
  }

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
                  children: entry.tags.map(pill).toList(),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget itemsView(List<Entry> list, bool wide) {
    list = list.where(matches).toList();
    if (list.isEmpty) {
      return empty(
        query.isNotEmpty ? 'Nothing matches yet.' : 'An idea belongs here.',
        query.isNotEmpty
            ? 'Try a different word or clear your search.'
            : 'Save a link, write a note, or add a photo.',
        Icons.bookmark_border,
      );
    }
    return LayoutBuilder(
      builder: (context, s) {
        final cols = s.maxWidth > 1050
            ? 3
            : s.maxWidth > 580
            ? 2
            : 1;
        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: list
              .map(
                (e) => SizedBox(
                  width: (s.maxWidth - (cols - 1) * 18) / cols,
                  child: itemCard(e),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget previewStatus(Entry e, {bool compact = false}) {
    final status = e.text('previewStatus');
    final loading = status == 'loading';
    final label = switch (status) {
      'loading' => 'Loading preview…',
      'ready' => 'Preview loaded',
      'no-image' => 'This page has no preview image.',
      'image-unavailable' => 'Page loaded · image unavailable',
      'unavailable' => 'Preview unavailable',
      _ => 'Preview not loaded',
    };
    if (compact && status == 'ready') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (loading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  status == 'ready'
                      ? Icons.check_circle_outline
                      : Icons.image_outlined,
                  size: 14,
                  color: muted,
                ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
              if (!loading)
                TextButton(
                  onPressed: store.canEdit(e.project)
                      ? () => media.preview(e, force: true)
                      : null,
                  child: Text(
                    status == 'ready' ? 'Refresh' : 'Retry',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
          if (!compact && e.text('previewError').isNotEmpty)
            Text(
              e.text('previewError'),
              style: TextStyle(fontSize: 11, color: muted),
            ),
        ],
      ),
    );
  }

  Widget itemCard(Entry e) {
    final photo = e.text('photo');
    final hasPhoto = photo.isNotEmpty && store.blob(photo).existsSync();
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: e.kind == 'note'
          ? Color.lerp(surface, const Color(0xfffff3d7), .2)
          : surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: muted.withValues(alpha: .14)),
      ),
      child: InkWell(
        onTap: () => detail(e),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPhoto)
              Image.file(
                store.blob(photo),
                height: 162,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            else if (e.kind == 'link')
              Container(
                height: 123,
                padding: const EdgeInsets.all(23),
                color:
                    (domain(e).length.isEven
                            ? const Color(0xffccd8ce)
                            : const Color(0xffdbd6e9))
                        .withValues(alpha: .7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        domain(e),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff4b5450),
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    Icon(Icons.north_east, size: 21, color: Color(0xff4b5450)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 14, 21, 19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        e.kind == 'link'
                            ? Icons.link
                            : e.kind == 'photo'
                            ? Icons.photo_outlined
                            : Icons.notes,
                        size: 12,
                        color: muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          e.kind == 'link' ? domain(e) : e.kind.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: e.kind == 'link' ? 0 : 1.4,
                            color: muted,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => store.canEdit(e.project)
                            ? store.update(e, {'favorite': !e.flag('favorite')})
                            : message('This project is read-only.'),
                        tooltip: e.flag('favorite')
                            ? 'Remove favorite'
                            : 'Favorite',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          e.flag('favorite')
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 17,
                          color: e.flag('favorite') ? accent : muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.title.isEmpty ? e.text('previewTitle') : e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      letterSpacing: -.3,
                    ),
                  ),
                  if (e.kind == 'link') previewStatus(e, compact: true),
                  if (e.kind == 'link' && e.priceLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        e.priceLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (e.text('body').isNotEmpty ||
                      e.text('previewDescription').isNotEmpty) ...[
                    const SizedBox(height: 11),
                    Text(
                      e.text('body').isNotEmpty
                          ? e.text('body')
                          : e.text('previewDescription'),
                      maxLines: e.kind == 'note' ? 7 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted, height: 1.8),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (e.text('tags').isNotEmpty)
                        Flexible(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: e.tags.map(pill).toList(),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        e.text('created').length >= 10
                            ? e.text('created').substring(0, 10)
                            : '',
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget reminderContent() {
    final reminders =
        store.entries
            .where((e) => e.kind == 'reminder' && !e.deleted && matches(e))
            .toList()
          ..sort((a, b) {
            if (a.flag('done') != b.flag('done')) {
              return a.flag('done') ? 1 : -1;
            }
            return a.text('due').compareTo(b.text('due'));
          });
    if (reminders.isEmpty) {
      return empty(
        'Make a little room for later.',
        'Set a reminder on a project, link, or note.',
        Icons.notifications_none,
      );
    }
    return Column(
      children: reminders.map((e) {
        final due = DateTime.tryParse(e.text('due'))?.toLocal();
        return Card(
          elevation: 0,
          color: surface,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            leading: Checkbox(
              value: e.flag('done'),
              onChanged: (v) => store.completeReminder(e, v ?? false),
            ),
            title: Text(
              e.title,
              style: TextStyle(
                decoration: e.flag('done') ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(
              "${e.flag('done')
                  ? 'Completed'
                  : due != null && due.isBefore(DateTime.now())
                  ? 'Overdue'
                  : 'Upcoming'} · ${store.get(e.project)?.title ?? 'Project'} · ${due?.toString().substring(0, 16) ?? 'No date'}",
              style: TextStyle(fontSize: 11, color: muted),
            ),
            onTap: () {
              final target = store.get(e.text('target'));
              if (target != null) {
                if (target.kind == 'project') {
                  openProject(target.id);
                } else {
                  detail(target);
                }
              }
            },
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') editReminder(existing: e);
                if (v == 'snooze') {
                  store.update(e, {
                    'due': DateTime.now()
                        .add(const Duration(hours: 1))
                        .toUtc()
                        .toIso8601String(),
                    'done': false,
                  });
                }
                if (v == 'delete') remove(e);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit reminder')),
                PopupMenuItem(value: 'snooze', child: Text('Snooze 1 hour')),
                PopupMenuItem(value: 'delete', child: Text('Delete reminder')),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
