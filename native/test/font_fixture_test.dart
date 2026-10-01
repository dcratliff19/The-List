import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/fonts.dart';

void main() {
  testWidgets('default test typography uses proportional bundled glyphs', (
    tester,
  ) async {
    await loadTestFonts();
    // Material defaults to Roboto in widget tests on every host. Ahem would
    // give these equal-length strings identical widths, hiding a missing font.
    final family = ThemeData().textTheme.bodyMedium!.fontFamily;
    final narrow = TextPainter(
      text: TextSpan(
        text: 'iiiiiiii',
        style: TextStyle(fontFamily: family, fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final wide = TextPainter(
      text: TextSpan(
        text: 'WWWWWWWW',
        style: TextStyle(fontFamily: family, fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    try {
      expect(narrow.width, lessThan(wide.width));
    } finally {
      narrow.dispose();
      wide.dispose();
    }
  });
}
