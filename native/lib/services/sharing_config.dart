import 'dart:io';
import '../store.dart';

class SharingConfig {
  static const bundledServer = String.fromEnvironment('THE_LIST_SIGNAL_URL');
  static String endpoint(Store store) {
    final override = store.setting('sharing-server')?.trim() ?? '';
    if (override.isNotEmpty && override != 'http://127.0.0.1:5174') {
      return override;
    }
    final environment =
        Platform.environment['THE_LIST_SIGNAL_URL']?.trim() ?? '';
    if (environment.isNotEmpty) return environment;
    if (bundledServer.isNotEmpty) return bundledServer;
    return override;
  }
}
