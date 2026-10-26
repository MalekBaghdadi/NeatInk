import 'package:flutter/material.dart';

import '../features/settings/app_settings.dart';

/// NeatInk's Material 3 look: a calm notebook app built around a deep ink
/// indigo, quiet surfaces, rounded cards and roomy touch targets for tablets.
abstract final class AppTheme {
  /// Deep ink indigo. Every colour role is derived from this seed.
  static const Color seed = Color(0xFF2F3C8C);

  /// Corner radius of cards, sheets and grouped settings sections.
  static const double cardRadius = 20;

  /// Corner radius of smaller controls (inputs, menus, snack bars).
  static const double controlRadius = 14;

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  /// Maps the persisted [AppThemeMode] to Flutter's [ThemeMode].
  static ThemeMode themeModeFor(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final text = _textTheme(base.textTheme, scheme);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    const buttonMinSize = Size(64, 48);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        minVerticalPadding: 12,
        iconColor: scheme.onSurfaceVariant,
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(shape: controlShape),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(controlShape),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: buttonMinSize),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: buttonMinSize),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: buttonMinSize),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(minimumSize: const Size(0, 44)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }

  /// Slightly tighter, heavier headings over the default M3 type scale, so
  /// screen titles and section headers read as a clear hierarchy.
  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) =>
      base.copyWith(
        displaySmall: base.displaySmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        headlineMedium: base.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
        headlineSmall: base.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: base.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ).apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      );
}
