import 'package:flutter/material.dart';

import 'linear_tokens.dart';

class LinearTheme {
  static ThemeData dark() {
    final chrome = const LinearThemeTokens();
    final colorScheme =
        const ColorScheme.dark(
          primary: LinearPalette.brandIndigo,
          secondary: LinearPalette.accentViolet,
          surface: LinearPalette.surface,
          error: LinearPalette.danger,
        ).copyWith(
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: LinearPalette.textPrimary,
          surfaceContainerLowest: LinearPalette.canvas,
          surfaceContainerLow: LinearPalette.panel,
          surfaceContainer: LinearPalette.surface,
          surfaceContainerHigh: LinearPalette.surfaceElevated,
          surfaceContainerHighest: LinearPalette.surfaceHover,
          outline: LinearPalette.borderStrong,
          outlineVariant: LinearPalette.borderStandard,
          surfaceTint: Colors.transparent,
        );

    return _buildTheme(
      brightness: Brightness.dark,
      chrome: chrome,
      colorScheme: colorScheme,
    );
  }

  static ThemeData light() {
    final chrome = const LinearThemeTokens.light();
    final colorScheme =
        const ColorScheme.light(
          primary: LinearPalette.brandIndigo,
          secondary: LinearPalette.accentViolet,
          surface: LinearPalette.lightSurface,
          error: LinearPalette.danger,
        ).copyWith(
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: LinearPalette.lightTextPrimary,
          surfaceContainerLowest: LinearPalette.lightCanvas,
          surfaceContainerLow: LinearPalette.lightPanel,
          surfaceContainer: LinearPalette.lightSurface,
          surfaceContainerHigh: LinearPalette.lightSurfaceElevated,
          surfaceContainerHighest: LinearPalette.lightSurfaceHover,
          outline: LinearPalette.lightBorderStrong,
          outlineVariant: LinearPalette.lightBorderStandard,
          surfaceTint: Colors.transparent,
        );

    return _buildTheme(
      brightness: Brightness.light,
      chrome: chrome,
      colorScheme: colorScheme,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required LinearThemeTokens chrome,
    required ColorScheme colorScheme,
  }) {
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: chrome.canvas,
      canvasColor: chrome.canvas,
      cardColor: chrome.surface,
      dividerColor: chrome.borderSubtle,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[chrome],
      textTheme: _buildTextTheme(base.textTheme, chrome),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: chrome.surface,
        margin: EdgeInsets.zero,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: LinearRadius.card,
          side: BorderSide(color: chrome.borderStandard),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: chrome.surface,
        surfaceTintColor: Colors.transparent,
        barrierColor: chrome.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: LinearRadius.panel,
          side: BorderSide(color: chrome.borderStandard),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: chrome.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: LinearRadius.panel),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: chrome.textSecondary,
        textColor: chrome.textPrimary,
      ),
      dividerTheme: DividerThemeData(
        color: chrome.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: chrome.textSecondary),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: chrome.brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: LinearSpacing.md,
            vertical: LinearSpacing.sm,
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: LinearRadius.control,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: chrome.textPrimary,
          side: BorderSide(color: chrome.borderStandard),
          padding: const EdgeInsets.symmetric(
            horizontal: LinearSpacing.md,
            vertical: LinearSpacing.sm,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: LinearRadius.control,
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: chrome.textSecondary,
          padding: const EdgeInsets.symmetric(
            horizontal: LinearSpacing.sm,
            vertical: LinearSpacing.xs,
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: chrome.panel,
        disabledColor: chrome.panel,
        selectedColor: chrome.surfaceHover,
        secondarySelectedColor: chrome.surfaceHover,
        side: BorderSide(color: chrome.borderStandard),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          color: chrome.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: chrome.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: LinearSpacing.xs,
          vertical: 2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: chrome.panel,
        hintStyle: TextStyle(color: chrome.textQuaternary, fontSize: 14),
        labelStyle: TextStyle(color: chrome.textSecondary, fontSize: 14),
        helperStyle: TextStyle(color: chrome.textTertiary, fontSize: 12),
        prefixIconColor: chrome.textTertiary,
        suffixIconColor: chrome.textTertiary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LinearSpacing.md,
          vertical: LinearSpacing.sm,
        ),
        border: _inputBorder(color: chrome.borderStandard),
        enabledBorder: _inputBorder(color: chrome.borderStandard),
        focusedBorder: _inputBorder(color: chrome.accent, width: 1.4),
        errorBorder: _inputBorder(color: chrome.danger),
        focusedErrorBorder: _inputBorder(color: chrome.danger, width: 1.4),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return chrome.textPrimary;
            }
            return chrome.textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return chrome.surfaceHover;
            }
            return chrome.panel;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: chrome.borderStandard),
          ),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: LinearRadius.control),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: chrome.panel,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? chrome.textPrimary
                : chrome.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? chrome.textPrimary
                : chrome.textTertiary,
          );
        }),
        indicatorColor: chrome.surfaceHover,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: chrome.brand,
        linearTrackColor: chrome.panel,
        circularTrackColor: chrome.panel,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: chrome.surfaceElevated,
          borderRadius: LinearRadius.control,
          border: Border.all(color: chrome.borderStandard),
        ),
        textStyle: TextStyle(color: chrome.textPrimary, fontSize: 12),
      ),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base, LinearThemeTokens chrome) {
    return base
        .copyWith(
          displayLarge: base.displayLarge?.copyWith(
            fontSize: 48,
            height: 1,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.05,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.6,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontSize: 20,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.25,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: 18,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 16,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.45,
            letterSpacing: 0,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.45,
            letterSpacing: 0,
          ),
          bodySmall: base.bodySmall?.copyWith(
            fontSize: 12.5,
            height: 1.4,
            letterSpacing: 0.05,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontSize: 11,
            height: 1.2,
            color: chrome.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(bodyColor: chrome.textPrimary, displayColor: chrome.textPrimary);
  }

  static OutlineInputBorder _inputBorder({
    required Color color,
    double width = 1,
  }) {
    return OutlineInputBorder(
      borderRadius: LinearRadius.control,
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
