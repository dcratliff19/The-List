import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('../screenshots/$name.png').writeAsBytes(bytes, flush: true);
      return true;
    },
  );
}
