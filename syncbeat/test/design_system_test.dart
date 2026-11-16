import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/theme/syncbeat_theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('$brightness text and action pairs meet WCAG AA', () {
      final theme = SyncBeatTheme.build(brightness);
      final c = theme.colorScheme;
      for (final pair in [
        (c.onSurface, c.surface),
        (
          theme.extension<SyncBeatStatusColors>()!.success,
          c.surfaceContainerLow,
        ),
        (
          theme.extension<SyncBeatStatusColors>()!.warning,
          c.surfaceContainerLow,
        ),
        (c.onSurfaceVariant, c.surface),
        (c.onSurfaceVariant, theme.scaffoldBackgroundColor),
        (c.primary, c.surface),
        (c.onPrimary, c.primary),
        (c.secondary, c.surface),
        (c.tertiary, c.surface),
        (c.onErrorContainer, c.errorContainer),
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, isNot(Colors.black));
    });
  }
}
