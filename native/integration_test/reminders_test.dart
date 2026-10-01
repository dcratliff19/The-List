import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:the_list/store.dart';
import 'package:the_list/services/reminders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native notifications schedule and cancel on completion', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp(
      'the-list-notifications-',
    );
    final store = Store(dir);
    final reminders = ReminderService(store);
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Testing native reminder scheduling')),
          ),
        ),
      );
      await reminders.initialize();
      expect(reminders.ready, isTrue, reason: reminders.status);
      final pid = store.create('project', '', {'title': 'Notification test'});
      final id = store.create('reminder', pid, {
        'title': 'Integration test reminder',
        'target': pid,
        'due': DateTime.now()
            .add(const Duration(minutes: 10))
            .toUtc()
            .toIso8601String(),
        'done': false,
      });
      expect(await reminders.enable(), isTrue);
      await reminders.reconcile();
      final pending = await reminders.plugin.pendingNotificationRequests();
      expect(
        pending.any((n) => n.id == reminders.notificationId(id)),
        isTrue,
        reason: reminders.status,
      );
      store.update(store.get(id)!, {'done': true});
      await reminders.reconcile();
      final after = await reminders.plugin.pendingNotificationRequests();
      expect(after.any((n) => n.id == reminders.notificationId(id)), isFalse);
    } finally {
      await reminders.disable();
      reminders.dispose();
      store.dispose();
      await dir.delete(recursive: true);
    }
  });
}
