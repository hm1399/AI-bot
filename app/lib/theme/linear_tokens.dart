import 'package:flutter/material.dart';

class LinearPalette {
  static const Color canvas = Color(0xFF08090A);
  static const Color panel = Color(0xFF0F1011);
  static const Color surface = Color(0xFF191A1B);
  static const Color surfaceHover = Color(0xFF28282C);
  static const Color surfaceElevated = Color(0xFF1F2023);
  static const Color textPrimary = Color(0xFFF7F8F8);
  static const Color textSecondary = Color(0xFFD0D6E0);
  static const Color textTertiary = Color(0xFF8A8F98);
  static const Color textQuaternary = Color(0xFF62666D);
  static const Color brandIndigo = Color(0xFF5E6AD2);
  static const Color accentViolet = Color(0xFF7170FF);
  static const Color accentHover = Color(0xFF828FFF);
  static const Color success = Color(0xFF27A644);
  static const Color successSoft = Color(0xFF10B981);
  static const Color warning = Color(0xFFCA8A04);
  static const Color danger = Color(0xFFDC2626);
  static const Color borderSubtle = Color(0x14FFFFFF);
  static const Color borderStandard = Color(0x1FFFFFFF);
  static const Color borderStrong = Color(0xFF34343A);
  static const Color overlay = Color(0xD9000000);
}

class LinearSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

class LinearRadius {
  static const BorderRadius micro = BorderRadius.all(Radius.circular(2));
  static const BorderRadius small = BorderRadius.all(Radius.circular(4));
  static const BorderRadius control = BorderRadius.all(Radius.circular(6));
  static const BorderRadius card = BorderRadius.all(Radius.circular(8));
  static const BorderRadius panel = BorderRadius.all(Radius.circular(12));
  static const BorderRadius large = BorderRadius.all(Radius.circular(22));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

@immutable
class LinearThemeTokens extends ThemeExtension<LinearThemeTokens> {
  const LinearThemeTokens({
    this.canvas = LinearPalette.canvas,
    this.panel = LinearPalette.panel,
    this.surface = LinearPalette.surface,
    this.surfaceHover = LinearPalette.surfaceHover,
    this.surfaceElevated = LinearPalette.surfaceElevated,
    this.textPrimary = LinearPalette.textPrimary,
    this.textSecondary = LinearPalette.textSecondary,
    this.textTertiary = LinearPalette.textTertiary,
    this.textQuaternary = LinearPalette.textQuaternary,
    this.brand = LinearPalette.brandIndigo,
    this.accent = LinearPalette.accentViolet,
    this.success = LinearPalette.success,
    this.warning = LinearPalette.warning,
    this.danger = LinearPalette.danger,
    this.borderSubtle = LinearPalette.borderSubtle,
    this.borderStandard = LinearPalette.borderStandard,
    this.borderStrong = LinearPalette.borderStrong,
    this.overlay = LinearPalette.overlay,
  });

  final Color canvas;
  final Color panel;
  final Color surface;
  final Color surfaceHover;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textQuaternary;
  final Color brand;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color borderSubtle;
  final Color borderStandard;
  final Color borderStrong;
  final Color overlay;

  @override
  LinearThemeTokens copyWith({
    Color? canvas,
    Color? panel,
    Color? surface,
    Color? surfaceHover,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textQuaternary,
    Color? brand,
    Color? accent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? borderSubtle,
    Color? borderStandard,
    Color? borderStrong,
    Color? overlay,
  }) {
    return LinearThemeTokens(
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      surface: surface ?? this.surface,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textQuaternary: textQuaternary ?? this.textQuaternary,
      brand: brand ?? this.brand,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStandard: borderStandard ?? this.borderStandard,
      borderStrong: borderStrong ?? this.borderStrong,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  LinearThemeTokens lerp(
    covariant ThemeExtension<LinearThemeTokens>? other,
    double t,
  ) {
    if (other is! LinearThemeTokens) {
      return this;
    }
    return LinearThemeTokens(
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      panel: Color.lerp(panel, other.panel, t) ?? panel,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceHover:
          Color.lerp(surfaceHover, other.surfaceHover, t) ?? surfaceHover,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
          surfaceElevated,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textTertiary:
          Color.lerp(textTertiary, other.textTertiary, t) ?? textTertiary,
      textQuaternary:
          Color.lerp(textQuaternary, other.textQuaternary, t) ?? textQuaternary,
      brand: Color.lerp(brand, other.brand, t) ?? brand,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      borderSubtle:
          Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      borderStandard:
          Color.lerp(borderStandard, other.borderStandard, t) ?? borderStandard,
      borderStrong:
          Color.lerp(borderStrong, other.borderStrong, t) ?? borderStrong,
      overlay: Color.lerp(overlay, other.overlay, t) ?? overlay,
    );
  }
}

extension LinearThemeContext on BuildContext {
  LinearThemeTokens get linear =>
      Theme.of(this).extension<LinearThemeTokens>() ??
      const LinearThemeTokens();
}
