import 'dart:io';
import 'package:flutter/services.dart';

/// Loads real glyphs instead of Flutter's fixed-width Ahem test font.
Future<void> loadTestFonts() async {
  // Widget tests default to Android typography (Roboto), including on Linux
  // and macOS. Use a bundled font for that family so CI needs no system fonts.
  final text = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  await text.load();

  // Preserve the native Windows metrics used by the existing screenshots.
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
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}
