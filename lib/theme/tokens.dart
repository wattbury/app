import 'package:flutter/material.dart';

/// Colour world "Signal" (RAL signal and traffic colours), taken from design/clickdummy.html.
/// Light and dark are separate selections, not an automatic inversion.
@immutable
class WbColors extends ThemeExtension<WbColors> {
  final Color appBg, card, fg, muted, sep, accent, good, warn, crit;
  final Color info, solar, solar2, battery, house, grid, wallbox;
  final Color pastelGreen, pastelYellow, pastelBlue, pastelPeach, pastelGrey;

  /// Translucent sub-tiles on colour cards.
  final Color sub, sub2;

  /// Chart series, validated for colour-vision deficiencies in the click dummy (dataviz check).
  final Color sSolar, sPurchase, sBatteryOut, sHouse, sFeedIn, sBatteryIn, grid1, axis, ink3;

  const WbColors({
    required this.appBg,
    required this.card,
    required this.fg,
    required this.muted,
    required this.sep,
    required this.accent,
    required this.good,
    required this.warn,
    required this.crit,
    required this.info,
    required this.solar,
    required this.solar2,
    required this.battery,
    required this.house,
    required this.grid,
    required this.wallbox,
    required this.pastelGreen,
    required this.pastelYellow,
    required this.pastelBlue,
    required this.pastelPeach,
    required this.pastelGrey,
    required this.sub,
    required this.sub2,
    required this.sSolar,
    required this.sPurchase,
    required this.sBatteryOut,
    required this.sHouse,
    required this.sFeedIn,
    required this.sBatteryIn,
    required this.grid1,
    required this.axis,
    required this.ink3,
  });

  static const light = WbColors(
    appBg: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    fg: Color(0xFF111111),
    muted: Color(0xFF6B6F76),
    sep: Color(0x243C3C43),
    accent: Color(0xFF2A7A3D),
    good: Color(0xFF0CA30C),
    warn: Color(0xFFFAB219),
    crit: Color(0xFFD03B3B),
    info: Color(0xFF383E42),
    solar: Color(0xFFE69500),
    solar2: Color(0xFFF5AB00),
    battery: Color(0xFF237F52),
    house: Color(0xFFC1121C),
    grid: Color(0xFF1F4E8C),
    wallbox: Color(0xFF924E7D),
    pastelGreen: Color(0xFFE4F1EA),
    pastelYellow: Color(0xFFFDF0CF),
    pastelBlue: Color(0xFFE2E9F4),
    pastelPeach: Color(0xFFF8E3E3),
    pastelGrey: Color(0xFFE9ECEE),
    sub: Color(0x29FFFFFF),
    sub2: Color(0x47FFFFFF),
    sSolar: Color(0xFF9E7A23),
    sPurchase: Color(0xFF36A3C8),
    sBatteryOut: Color(0xFF8D6CC2),
    sHouse: Color(0xFFC15C67),
    sFeedIn: Color(0xFF547ECD),
    sBatteryIn: Color(0xFF539344),
    grid1: Color(0xFFE1E0D9),
    axis: Color(0xFFC3C2B7),
    ink3: Color(0xFF898781),
  );

  static const dark = WbColors(
    appBg: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    fg: Color(0xFFF2F2F2),
    muted: Color(0xFF9A9CA3),
    sep: Color(0x99545458),
    accent: Color(0xFF3C9A52),
    good: Color(0xFF0CA30C),
    warn: Color(0xFFFAB219),
    crit: Color(0xFFD03B3B),
    info: Color(0xFF2B3034),
    solar: Color(0xFFD99400),
    solar2: Color(0xFFE5A600),
    battery: Color(0xFF1C6642),
    house: Color(0xFF9E0F17),
    grid: Color(0xFF1A4075),
    wallbox: Color(0xFF773F66),
    pastelGreen: Color(0xFF203528),
    pastelYellow: Color(0xFF3A3014),
    pastelBlue: Color(0xFF1F2A3B),
    pastelPeach: Color(0xFF3B2224),
    pastelGrey: Color(0xFF262B2F),
    sub: Color(0x1FFFFFFF),
    sub2: Color(0x38FFFFFF),
    sSolar: Color(0xFF98741A),
    sPurchase: Color(0xFF299ABE),
    sBatteryOut: Color(0xFF8766BB),
    sHouse: Color(0xFFBA5661),
    sFeedIn: Color(0xFF4E78C7),
    sBatteryIn: Color(0xFF4D8C3E),
    grid1: Color(0xFF2C2C2A),
    axis: Color(0xFF383835),
    ink3: Color(0xFF898781),
  );

  /// Text on colour cards is always white, also on yellow.
  static const on = Colors.white;
  static const onDim = Color(0xD1FFFFFF);

  @override
  WbColors copyWith() => this;

  @override
  WbColors lerp(WbColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension WbColorsContext on BuildContext {
  WbColors get wb => Theme.of(this).extension<WbColors>()!;
}

/// Sora for numbers and titles; it ships as a variable font, so weights go through font variations.
TextStyle sora(double size, {double weight = 600, Color? color, double? letterSpacing, double? height}) => TextStyle(
  fontFamily: 'Sora',
  fontSize: size,
  fontVariations: [FontVariation.weight(weight)],
  fontWeight: weight >= 600 ? FontWeight.w600 : FontWeight.w400,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
  fontFeatures: const [FontFeature.tabularFigures()],
);

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? WbColors.dark : WbColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: b,
  ).copyWith(primary: c.accent, surface: c.appBg, onSurface: c.fg);
  return ThemeData(
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.appBg,
    extensions: [c],
    dividerColor: c.sep,
    splashFactory: NoSplash.splashFactory,
  );
}
