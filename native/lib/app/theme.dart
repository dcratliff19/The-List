import 'dart:io';
import 'package:flutter/material.dart';
import '../store.dart';

ThemeData workspaceTheme(Store store) {
  final dark = store.setting('theme') == 'dark';
  final savedAccent = store.setting('accent') ?? '5848D9';
  final seed = Color(
    0xff000000 | (int.tryParse(savedAccent, radix: 16) ?? 0x5848D9),
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(surface: dark ? const Color(0xff212229) : Colors.white);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xff191a20)
        : const Color(0xfffafaf8),
    fontFamily: Platform.isWindows ? 'Segoe UI' : null,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    ),
  );
}
