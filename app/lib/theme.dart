import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The app's look, chosen in Settings, General; each comes light and dark.
enum ThemePalette {
  /// The Tildeck brand: a deep teal band beside the content.
  tildeck,

  /// One calm surface throughout, the band included.
  midnight,

  /// Bright and open, the band as light as the page.
  daylight,
}

/// The Tildeck design tokens: a light and a dark value per name, per
/// palette. Tildeck's values are the admin panel's
/// (panel/app/assets/css/tailwind.css).
@immutable
class TildeckColors extends ThemeExtension<TildeckColors> {
  const TildeckColors({
    required this.page,
    required this.surface,
    required this.raised,
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
    required this.shadow,
  });

  /// The window behind everything.
  final Color page;

  /// Panels, dialogs, menus, and fields.
  final Color surface;

  /// What sits on a surface and can be picked: cards, list rows.
  final Color raised;
  final Color line;
  final Color tint;
  final Color ink;
  final Color muted;
  final Color brand;
  final Color brandBright;
  final Color brandContrast;
  final Color success;
  final Color danger;

  /// The band that carries the brand: the sidebar and the phone's bar.
  final Color desk;
  final Color deskInk;
  final Color deskMuted;
  final Color deskBright;

  /// The colour of soft shadows under cards, menus, and panels.
  final Color shadow;

  static const light = TildeckColors(
    page: Color(0xFFEFF4F4),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
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
    shadow: Color(0x1A0E181C),
  );

  static const dark = TildeckColors(
    page: Color(0xFF081013),
    surface: Color(0xFF101C20),
    raised: Color(0xFF142328),
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
    shadow: Color(0x66000000),
  );

  static const midnightDark = TildeckColors(
    page: Color(0xFF0B1416),
    surface: Color(0xFF0F1C1F),
    raised: Color(0xFF14252A),
    line: Color(0xFF1D3236),
    tint: Color(0xFF12302F),
    ink: Color(0xFFE6F0EF),
    muted: Color(0xFF8AA3A3),
    brand: Color(0xFF2DD4BF),
    brandBright: Color(0xFF5EEAD4),
    brandContrast: Color(0xFF062022),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF87171),
    desk: Color(0xFF0B1416),
    deskInk: Color(0xFFE6F0EF),
    deskMuted: Color(0xFF9FB3B3),
    deskBright: Color(0xFF5EEAD4),
    shadow: Color(0x73000000),
  );

  static const midnightLight = TildeckColors(
    page: Color(0xFFE9EEEF),
    surface: Color(0xFFF6F8F8),
    raised: Color(0xFFFFFFFF),
    line: Color(0xFFD5DFE0),
    tint: Color(0xFFDDF0EC),
    ink: Color(0xFF0E181C),
    muted: Color(0xFF55676B),
    brand: Color(0xFF0F766E),
    brandBright: Color(0xFF14B8A6),
    brandContrast: Color(0xFFFFFFFF),
    success: Color(0xFF15803D),
    danger: Color(0xFFB91C1C),
    desk: Color(0xFFE9EEEF),
    deskInk: Color(0xFF0E181C),
    deskMuted: Color(0xFF55676B),
    deskBright: Color(0xFF0F766E),
    shadow: Color(0x170E181C),
  );

  static const daylightLight = TildeckColors(
    page: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF7FAFA),
    line: Color(0xFFE3EAEB),
    tint: Color(0xFFE8F4F2),
    ink: Color(0xFF101A1E),
    muted: Color(0xFF5B6D71),
    brand: Color(0xFF0F766E),
    brandBright: Color(0xFF14B8A6),
    brandContrast: Color(0xFFFFFFFF),
    success: Color(0xFF15803D),
    danger: Color(0xFFB91C1C),
    desk: Color(0xFFF3F6F6),
    deskInk: Color(0xFF101A1E),
    deskMuted: Color(0xFF4C5F63),
    deskBright: Color(0xFF0F766E),
    shadow: Color(0x14101A1E),
  );

  static const daylightDark = TildeckColors(
    page: Color(0xFF151D20),
    surface: Color(0xFF1A2427),
    raised: Color(0xFF202C30),
    line: Color(0xFF2C3A3E),
    tint: Color(0xFF173533),
    ink: Color(0xFFEEF4F4),
    muted: Color(0xFF9AAEB0),
    brand: Color(0xFF5EEAD4),
    brandBright: Color(0xFF99F6E4),
    brandContrast: Color(0xFF062022),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF87171),
    desk: Color(0xFF1A2427),
    deskInk: Color(0xFFEEF4F4),
    deskMuted: Color(0xFF9AAEB0),
    deskBright: Color(0xFF5EEAD4),
    shadow: Color(0x59000000),
  );

  static TildeckColors of(ThemePalette palette, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (palette) {
      ThemePalette.tildeck => dark ? TildeckColors.dark : TildeckColors.light,
      ThemePalette.midnight => dark ? midnightDark : midnightLight,
      ThemePalette.daylight => dark ? daylightDark : daylightLight,
    };
  }

  @override
  TildeckColors copyWith() => this;

  @override
  TildeckColors lerp(TildeckColors? other, double t) => t < 0.5 || other == null ? this : other;
}

extension TildeckTheme on BuildContext {
  TildeckColors get colors => Theme.of(this).extension<TildeckColors>()!;
}

/// Whether the app is laid out for a mouse: smaller controls and text.
bool get _desktop => switch (defaultTargetPlatform) {
  TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
  _ => false,
};

/// One scale for the whole app: a step smaller on the desktop, where a
/// pointer is precise and more fits on the screen, as in other desktop
/// tools. Material's letter spacing is removed: it pulls Hebrew letters
/// apart, and Heebo is spaced for both scripts as it is.
TextTheme _scale(TextTheme t, Color ink, Color muted) {
  final d = _desktop;
  TextStyle? s(TextStyle? base, double size, FontWeight weight, {double height = 1.4, Color? color}) =>
      base?.copyWith(fontSize: size, fontWeight: weight, height: height, letterSpacing: 0, color: color ?? ink);
  return t.copyWith(
    displayLarge: s(t.displayLarge, d ? 44 : 48, FontWeight.w800, height: 1.15),
    displayMedium: s(t.displayMedium, d ? 36 : 40, FontWeight.w800, height: 1.15),
    displaySmall: s(t.displaySmall, d ? 30 : 32, FontWeight.w800, height: 1.2),
    headlineLarge: s(t.headlineLarge, d ? 26 : 30, FontWeight.w800, height: 1.2),
    headlineMedium: s(t.headlineMedium, d ? 22 : 26, FontWeight.w800, height: 1.25),
    headlineSmall: s(t.headlineSmall, d ? 20 : 22, FontWeight.w700, height: 1.25),
    titleLarge: s(t.titleLarge, d ? 18 : 20, FontWeight.w700, height: 1.3),
    titleMedium: s(t.titleMedium, d ? 14.5 : 16, FontWeight.w600),
    titleSmall: s(t.titleSmall, d ? 13 : 14, FontWeight.w600),
    bodyLarge: s(t.bodyLarge, d ? 14 : 16, FontWeight.w400, height: 1.5),
    bodyMedium: s(t.bodyMedium, d ? 13.5 : 14, FontWeight.w400, height: 1.5),
    bodySmall: s(t.bodySmall, d ? 12 : 12.5, FontWeight.w400, color: muted),
    labelLarge: s(t.labelLarge, d ? 13.5 : 14, FontWeight.w600),
    labelMedium: s(t.labelMedium, d ? 12 : 12.5, FontWeight.w600),
    labelSmall: s(t.labelSmall, d ? 11 : 11.5, FontWeight.w600, color: muted),
  );
}

ThemeData buildTheme(Brightness brightness, {ThemePalette palette = ThemePalette.tildeck}) {
  final c = TildeckColors.of(palette, brightness);
  final d = _desktop;
  // One shape and height for every button and field, as the panel's .btn.
  const radius = 8.0;
  final control = d ? 38.0 : 46.0;
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  final scheme = ColorScheme.fromSeed(
    seedColor: c.brand,
    brightness: brightness,
    primary: c.brand,
    onPrimary: c.brandContrast,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    outline: c.line,
    outlineVariant: c.line,
    surfaceContainerLowest: c.page,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.raised,
    surfaceContainerHighest: c.raised,
    secondaryContainer: c.tint,
    onSecondaryContainer: c.ink,
    error: c.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Heebo',
    scaffoldBackgroundColor: c.page,
    canvasColor: c.page,
    dividerColor: c.line,
    visualDensity: d ? VisualDensity.compact : VisualDensity.standard,
    extensions: [c],
  );
  final label = TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: d ? 13.5 : 15);
  final buttonPadding = EdgeInsets.symmetric(horizontal: d ? 14 : 18);
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide(color: color, width: width),
  );
  return base.copyWith(
    textTheme: _scale(base.textTheme, c.ink, c.muted),
    iconTheme: IconThemeData(color: c.muted, size: d ? 20 : 22),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      isDense: d,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: d ? 12 : 14),
      hintStyle: TextStyle(color: c.muted),
      labelStyle: TextStyle(color: c.muted),
      floatingLabelStyle: TextStyle(color: c.brand, fontWeight: FontWeight.w600),
      helperStyle: TextStyle(color: c.muted, fontSize: d ? 12 : 12.5),
      border: border(c.line),
      enabledBorder: border(c.line),
      focusedBorder: border(c.brand, 1.6),
      errorBorder: border(c.danger),
      focusedErrorBorder: border(c.danger, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.brandContrast,
        minimumSize: Size(0, control),
        padding: buttonPadding,
        shape: rounded,
        textStyle: label.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    // The panel's .btn-quiet: a quiet border and the text's own colour.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        minimumSize: Size(0, control),
        padding: buttonPadding,
        shape: rounded,
        side: BorderSide(color: c.line),
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.brand,
        minimumSize: Size(0, d ? 32 : 40),
        padding: EdgeInsets.symmetric(horizontal: d ? 10 : 12),
        shape: rounded,
        textStyle: label,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.muted, shape: rounded),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: c.surface,
        foregroundColor: c.muted,
        selectedBackgroundColor: c.tint,
        selectedForegroundColor: c.ink,
        side: BorderSide(color: c.line),
        shape: rounded,
        minimumSize: Size(0, control),
        textStyle: label,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.raised,
      selectedColor: c.tint,
      side: BorderSide(color: c.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      labelStyle: TextStyle(fontFamily: 'Heebo', fontSize: d ? 12.5 : 13, color: c.ink),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    cardTheme: CardThemeData(
      color: c.raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.muted,
      textColor: c.ink,
      dense: d,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      contentPadding: EdgeInsets.symmetric(horizontal: d ? 12 : 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: c.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.line),
      ),
      titleTextStyle: TextStyle(fontFamily: 'Heebo', fontSize: d ? 18 : 20, fontWeight: FontWeight.w700, color: c.ink),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: c.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.line),
      ),
      textStyle: TextStyle(fontFamily: 'Heebo', fontSize: d ? 13.5 : 14.5, color: c.ink),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(c.shadow),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: c.line),
          ),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.ink.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(fontFamily: 'Heebo', fontSize: 12, color: c.page),
      waitDuration: const Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(fontFamily: 'Heebo', fontSize: 14, color: c.page),
      actionTextColor: c.brandBright,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.page,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontFamily: 'Heebo', fontSize: d ? 18 : 20, fontWeight: FontWeight.w700, color: c.ink),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brandContrast : c.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brand : c.surface),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : c.line,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(c.muted.withValues(alpha: 0.35)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.brand, linearTrackColor: c.line),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
