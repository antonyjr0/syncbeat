import 'package:flutter/material.dart';

@immutable
class SyncBeatStatusColors extends ThemeExtension<SyncBeatStatusColors> {
  const SyncBeatStatusColors({required this.success, required this.warning});
  final Color success;
  final Color warning;

  static SyncBeatStatusColors of(BuildContext context) =>
      Theme.of(context).extension<SyncBeatStatusColors>() ??
      const SyncBeatStatusColors(
        success: Color(0xFF216849),
        warning: Color(0xFF805300),
      );

  @override
  SyncBeatStatusColors copyWith({Color? success, Color? warning}) =>
      SyncBeatStatusColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
      );

  @override
  SyncBeatStatusColors lerp(covariant SyncBeatStatusColors? other, double t) =>
      other == null
      ? this
      : SyncBeatStatusColors(
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

/// Brand samples come from the original icon; UI tones adapt them for contrast.
abstract final class SyncBeatTheme {
  static const cyan = Color(0xFF75D1FD);
  static const blue = Color(0xFF6491FB);
  static const violet = Color(0xFFB562FA);

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(seedColor: blue, brightness: brightness)
        .copyWith(
          primary: dark ? cyan : const Color(0xFF2055A6),
          onPrimary: dark ? const Color(0xFF071123) : Colors.white,
          secondary: dark ? const Color(0xFFD2ACFF) : const Color(0xFF7040A0),
          onSecondary: dark ? const Color(0xFF29133F) : Colors.white,
          secondaryContainer: dark
              ? const Color(0xFF402559)
              : const Color(0xFFF0DEFF),
          onSecondaryContainer: dark
              ? const Color(0xFFF0DEFF)
              : const Color(0xFF29133F),
          tertiary: dark ? cyan : const Color(0xFF00658A),
          onTertiary: dark ? const Color(0xFF071123) : Colors.white,
          surface: dark ? const Color(0xFF111E34) : const Color(0xFFFCFCFF),
          onSurface: dark ? const Color(0xFFE7EDFA) : const Color(0xFF14213A),
          onSurfaceVariant: dark
              ? const Color(0xFFBAC6DB)
              : const Color(0xFF4D5D75),
          surfaceContainerLow: dark
              ? const Color(0xFF17263E)
              : const Color(0xFFF0F3FA),
          outline: dark ? const Color(0xFF8292AC) : const Color(0xFF687891),
          outlineVariant: dark
              ? const Color(0xFF34445F)
              : const Color(0xFFD1DAE8),
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      shape: WidgetStatePropertyAll(shape),
      // Material supplies hover/pressed/disabled overlays; retain keyboard focus.
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: colors.primary, width: 2)
            : null,
      ),
    );
    return base.copyWith(
      extensions: [
        SyncBeatStatusColors(
          success: dark ? const Color(0xFF85DDB0) : const Color(0xFF216849),
          warning: dark ? const Color(0xFFFFD180) : const Color(0xFF805300),
        ),
      ],
      scaffoldBackgroundColor: dark
          ? const Color(0xFF071123)
          : const Color(0xFFF5F7FC),
      textTheme: base.textTheme.apply(
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: shape.copyWith(side: BorderSide(color: colors.outlineVariant)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(style: button),
      textButtonTheme: TextButtonThemeData(style: button),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        shape: shape,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: TextStyle(color: colors.onInverseSurface),
      ),
      dividerTheme: DividerThemeData(color: colors.outlineVariant),
    );
  }
}
