import 'package:flutter/material.dart';

/// The Tildeck design tokens, the same values as the admin panel
/// (panel/app/assets/css/tailwind.css): a light and a dark value per name.
@immutable
class TildeckColors extends ThemeExtension<TildeckColors> {
  const TildeckColors({
    required this.page,
    required this.surface,
    required this.line,
    required this.tint,
    required this.ink,
    required this.muted,
    required this.brand,
    required this.brandBright,
    required this.brandContrast,
    required this.success,
    required this.danger,
    required this.desk,
    required this.deskInk,
    required this.deskMuted,
    required this.deskBright,
  });

  final Color page;
  final Color surface;
  final Color line;
  final Color tint;
  final Color ink;
  final Color muted;
  final Color brand;
  final Color brandBright;
  final Color brandContrast;
  final Color success;
  final Color danger;

  /// The dark band that carries the brand. Dark in both themes.
  final Color desk;
  final Color deskInk;
  final Color deskMuted;
  final Color deskBright;

  static const light = TildeckColors(
    page: Color(0xFFEFF4F4),
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFD2DDDE),
    tint: Color(0xFFDEF1EE),
    ink: Color(0xFF0E181C),
    muted: Color(0xFF54666B),
    brand: Color(0xFF0F766E),
    brandBright: Color(0xFF14B8A6),
    brandContrast: Color(0xFFFFFFFF),
    success: Color(0xFF15803D),
    danger: Color(0xFFB91C1C),
    desk: Color(0xFF13292D),
    deskInk: Color(0xFFE7F4F2),
    deskMuted: Color(0xFF97BCB8),
    deskBright: Color(0xFF5EEAD4),
  );

  static const dark = TildeckColors(
    page: Color(0xFF081013),
    surface: Color(0xFF101C20),
    line: Color(0xFF26383D),
    tint: Color(0xFF112C2D),
    ink: Color(0xFFEBF4F3),
    muted: Color(0xFF8DA4A7),
    brand: Color(0xFF2DD4BF),
    brandBright: Color(0xFF5EEAD4),
    brandContrast: Color(0xFF061A1A),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF87171),
    desk: Color(0xFF0C1E22),
    deskInk: Color(0xFFE7F4F2),
    deskMuted: Color(0xFF8AB2AE),
    deskBright: Color(0xFF5EEAD4),
  );

  @override
  TildeckColors copyWith() => this;

  @override
  TildeckColors lerp(TildeckColors? other, double t) => t < 0.5 || other == null ? this : other;
}

extension TildeckTheme on BuildContext {
  TildeckColors get colors => Theme.of(this).extension<TildeckColors>()!;
}

TextTheme _withoutLetterSpacing(TextTheme t) {
  TextStyle? zero(TextStyle? s) => s?.copyWith(letterSpacing: 0);
  return t.copyWith(
    displayLarge: zero(t.displayLarge),
    displayMedium: zero(t.displayMedium),
    displaySmall: zero(t.displaySmall),
    headlineLarge: zero(t.headlineLarge),
    headlineMedium: zero(t.headlineMedium),
    headlineSmall: zero(t.headlineSmall),
    titleLarge: zero(t.titleLarge),
    titleMedium: zero(t.titleMedium),
    titleSmall: zero(t.titleSmall),
    bodyLarge: zero(t.bodyLarge),
    bodyMedium: zero(t.bodyMedium),
    bodySmall: zero(t.bodySmall),
    labelLarge: zero(t.labelLarge),
    labelMedium: zero(t.labelMedium),
    labelSmall: zero(t.labelSmall),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? TildeckColors.dark : TildeckColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.brand,
    brightness: brightness,
    primary: c.brand,
    onPrimary: c.brandContrast,
    surface: c.surface,
    onSurface: c.ink,
    error: c.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Heebo',
    scaffoldBackgroundColor: c.page,
    extensions: [c],
  );
  return base.copyWith(
    // Material's default letter spacing pulls Hebrew letters apart; Heebo
    // is spaced for both scripts as it is.
    textTheme: _withoutLetterSpacing(base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.brand, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.brandContrast,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
  );
}
