import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../store.dart';
import '../domain/entry_query.dart';
import 'workspace_section.dart';
import '../services/media.dart';
import '../services/sync.dart';
import '../services/sharing_config.dart';
import '../services/reminders.dart';
import '../services/excel_backup.dart';
import '../services/project_pdf.dart';
import 'widgets/editor_dialog.dart';
import 'widgets/empty_workspace.dart';
import 'widgets/preview_status.dart';

part 'feed.dart';
part 'views/navigation.dart';
part 'views/library.dart';
part 'views/project.dart';
part 'views/board.dart';
part 'views/items.dart';
part 'views/reminders.dart';
part 'editors/projects.dart';
part 'editors/items.dart';
part 'editors/reminders.dart';
part 'editors/appearance.dart';
part 'editors/backups.dart';
part 'editors/settings.dart';
part 'editors/sharing.dart';
part 'features/forms.dart';
part 'features/planning.dart';
part 'features/comments.dart';
part 'features/organization.dart';
part 'features/capture.dart';
part 'features/today.dart';
part 'features/activity.dart';
part 'features/exports.dart';

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
  WorkspaceSection section = WorkspaceSection.projects;
  String filter = 'all', query = '';
  String? projectId;
  final search = TextEditingController();
  Timer? reminderClock;
  StreamSubscription<Uri>? captureSubscription;
  final captureChannel = const MethodChannel('thelist/capture');
  final pendingCaptures = <String>[];
  bool captureOpen = false;
  Future<void> receiveCapture(String text) async {
    if (!mounted || text.isEmpty || text.length > 32000) return;
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
        if (!mounted) return;
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
          await act(() async {
            final initial = await captureChannel.invokeMethod<String>(
              'getInitialText',
            );
            if (initial != null && mounted) await receiveCapture(initial);
          });
        });
      }
      if (Platform.isIOS) {
        WidgetsBinding.instance.addPostFrameCallback((_) => readAppleShares());
      }
      excelBackup.initialize();
      reminders.opened.addListener(openNotification);
      unawaited(act(sync.initialize));
      unawaited(act(media.repairMissing));
      unawaited(act(reminders.initialize));
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
    if (!mounted) return;
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
    pendingCaptures.clear();
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

  void rebuild(VoidCallback change) {
    if (mounted) setState(change);
  }

  void navigate(WorkspaceSection next) => rebuild(() {
    section = next;
    projectId = null;
    filter = 'all';
    query = '';
    search.clear();
  });
  void openProject(String id) => rebuild(() {
    projectId = id;
    section = WorkspaceSection.projects;
    filter = 'all';
    query = '';
    search.clear();
  });
  Widget iconAction(IconData icon, String label, VoidCallback action) =>
      IconButton(tooltip: label, onPressed: action, icon: Icon(icon, size: 19));
  Widget addButton(String label, VoidCallback action) => FilledButton.icon(
    onPressed: action,
    icon: Icon(Icons.add, size: 17),
    label: Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
  );
  Widget statusBadge(String text) => Container(
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
  bool matches(Entry entry) => EntryQuery(query).matches(entry);

  String domain(Entry e) =>
      Uri.tryParse(e.text('url'))?.host.replaceFirst('www.', '') ?? 'Web link';
  String get sectionTitle => section.title;
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
                  selectedIndex: WorkspaceSection.mobileDestinations
                      .indexOf(section)
                      .clamp(0, 4),
                  onDestinationSelected: (index) =>
                      navigate(WorkspaceSection.mobileDestinations[index]),
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
}
