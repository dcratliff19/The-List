import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:the_list/services/sync.dart';
import 'package:the_list/store.dart';

class _DelayedVault extends FlutterSecureStorage {
  final result = Completer<String?>();
  int reads = 0;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) {
    reads++;
    return result.future;
  }
}

void main() {
  test(
    'initialization is shared and cannot restore peers after disposal',
    () async {
      final store = Store(
        Directory.systemTemp,
        database: sqlite3.openInMemory(),
      );
      final vault = _DelayedVault();
      final sync = SyncService(store, vault: vault);
      final first = sync.initialize();
      expect(identical(first, sync.initialize()), isTrue);
      expect(vault.reads, 1);
      sync.dispose();
      store.dispose();
      // Invalid peer data would fail if initialization continued past disposal.
      vault.result.complete('[{"project":"stale"}]');
      await first;
      expect(sync.peers, isEmpty);
      expect(sync.error, isNull);
      await sync.initialize();
      expect(vault.reads, 1);
    },
  );
}
