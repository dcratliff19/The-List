import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../store.dart';
import 'linux_scheduler.dart';

/// Reconciles personal reminders with platform notification schedules.
/// Persisted due signatures prevent duplicate delivery after restarting the app.
class ReminderService extends ChangeNotifier {
  final Store store;
  final plugin = FlutterLocalNotificationsPlugin();
  late final linux = LinuxScheduler(store);
  final ValueNotifier<String?> opened = ValueNotifier(null);
  String status = 'Notifications are off. Reminders still appear in your list.';
  bool ready = false, running = false;
  Timer? timer, debounce;
  final scheduled = <String, String>{};
  ReminderService(this.store);
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    await linux.initialize();
    try {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          linux: LinuxInitializationSettings(
            defaultActionName: 'Open reminder',
          ),
          windows: WindowsInitializationSettings(
            appName: 'The List',
            appUserModelId: 'App.TheList.Desktop',
            guid: '7e84548c-b628-4663-9b90-627cf51f4917',
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          opened.value = response.payload;
        },
      );
      ready = true;
      if (!Platform.isLinux) {
        final launch = await plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp == true) {
          opened.value = launch?.notificationResponse?.payload;
        }
      }
      store.addListener(onChange);
      timer = Timer.periodic(const Duration(seconds: 20), (_) => reconcile());
      await reconcile();
    } catch (e) {
      status =
          'Notifications unavailable on this system. Your due list is still available.';
      notifyListeners();
    }
  }

  Future<bool> enable() async {
    if (!ready) {
      await initialize();
      if (!ready) return false;
    }
    bool allowed = true;
    if (Platform.isAndroid) {
      allowed =
          await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      allowed =
          await plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (Platform.isMacOS) {
      allowed =
          await plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    store.setSetting('notifications', allowed ? 'on' : 'off');
    if (!allowed) {
      status =
          'Permission was not granted. Enable notifications in system settings.';
      notifyListeners();
      return false;
    }
    await reconcile();
    return true;
  }

  int notificationId(String id) {
    final key = 'notification-id-$id';
    final old = store.setting(key);
    if (old != null) return int.parse(old);
    final next = int.parse(store.setting('notification-next') ?? '0') + 1;
    store.setSetting('notification-next', '$next');
    store.setSetting(key, '$next');
    return next;
  }

  void onChange() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () => reconcile());
  }

  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'project-reminders',
      'Project reminders',
      channelDescription: 'Reminders for The List projects, links, and notes',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );
  Future<void> reconcile() async {
    if (!ready || running) return;
    running = true;
    try {
      final enabled = store.setting('notifications') == 'on';
      final reminders = store.entries
          .where((e) => e.kind == 'reminder')
          .toList();
      final future = <Entry>[];
      for (final e in reminders) {
        final target = store.get(e.text('target'));
        final due = DateTime.tryParse(e.text('due'));
        if (!enabled ||
            e.deleted ||
            e.flag('done') ||
            target == null ||
            target.deleted ||
            store.get(e.project)?.deleted == true ||
            due == null) {
          if (scheduled.containsKey(e.id) ||
              store.setting('notification-active-${e.id}') == 'yes') {
            if (Platform.isLinux && linux.available) {
              await linux.cancel(e);
            } else {
              await plugin.cancel(id: notificationId(e.id));
            }
            scheduled.remove(e.id);
            store.setSetting('notification-active-${e.id}', 'no');
          }
          continue;
        }
        if (due.isAfter(DateTime.now())) {
          future.add(e);
          continue;
        }
        // A persisted due signature prevents duplicate catch-up alerts after restart.
        if (store.setting('notified-${e.id}') != e.text('due') &&
            (scheduled[e.id] != e.text('due'))) {
          await plugin.show(
            id: notificationId(e.id),
            title: e.title,
            body: store.get(e.project)?.title ?? 'The List',
            notificationDetails: details,
            payload: e.text('target'),
          );
          store.setSetting('notified-${e.id}', e.text('due'));
        } else if (scheduled[e.id] == e.text('due')) {
          store.setSetting('notified-${e.id}', e.text('due'));
        }
      }
      future.sort((a, b) => a.text('due').compareTo(b.text('due')));
      // iOS limits pending requests. Refill the nearest 60 on app resume / edit.
      final queue = Platform.isIOS ? future.take(60) : future;
      if (Platform.isIOS) {
        for (final e in future.skip(60)) {
          if (store.setting("notification-active-${e.id}") == "yes") {
            await plugin.cancel(id: notificationId(e.id));
            scheduled.remove(e.id);
            store.setSetting("notification-active-${e.id}", "no");
          }
        }
      }
      if (Platform.isLinux && linux.available) {
        for (final e in queue) {
          final signature = '${e.text('due')}|${e.title}';
          if (scheduled[e.id] == signature) continue;
          await linux.schedule(e);
          scheduled[e.id] = signature;
          store.setSetting('notification-active-${e.id}', 'yes');
          store.setSetting('notified-${e.id}', e.text('due'));
        }
      } else if (!Platform.isLinux) {
        for (final e in queue) {
          final signature = '${e.text('due')}|${e.title}';
          if (scheduled[e.id] == signature) continue;
          await plugin.cancel(id: notificationId(e.id));
          await plugin.zonedSchedule(
            id: notificationId(e.id),
            scheduledDate: tz.TZDateTime.from(
              DateTime.parse(e.text('due')),
              tz.UTC,
            ),
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: e.title,
            body: store.get(e.project)?.title ?? 'The List',
            payload: e.text('target'),
          );
          scheduled[e.id] = signature;
          store.setSetting('notification-active-${e.id}', 'yes');
          store.setSetting('notified-${e.id}', e.text('due'));
        }
      }
      status = !enabled
          ? 'Notifications are off. Reminders still appear in your list.'
          : Platform.isLinux
          ? (linux.available
                ? 'Notifications scheduled with your desktop session.'
                : 'Notifications enabled while The List is running. Install systemd, Python 3 and notify-send for closed-app delivery.')
          : 'Notifications enabled. Delivery follows your system settings.';
    } catch (e) {
      status =
          'Some notifications could not be scheduled. Check system permissions; the due list is available.';
    } finally {
      running = false;
      notifyListeners();
    }
  }

  Future<void> disable() async {
    store.setSetting('notifications', 'off');
    await reconcile();
  }

  @override
  void dispose() {
    timer?.cancel();
    debounce?.cancel();
    store.removeListener(onChange);
    opened.dispose();
    super.dispose();
  }
}
