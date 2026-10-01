import 'dart:io';
import 'package:flutter/services.dart';

/// Uses the app's real fonts so widget layout matches the desktop build.
Future<void> loadTestFonts() async {
  if (Platform.isWindows) {
    final font = FontLoader('Segoe UI')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/segoeui.ttf').readAsBytesSync(),
          ),
        ),
      );
    await font.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}
