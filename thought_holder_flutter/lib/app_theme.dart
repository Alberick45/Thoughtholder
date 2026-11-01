import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  final Color bg;
  final Color card;
  final Color line;
  final Color text;
  final Color mute;
  final Color gold;
  final Color goldBg;
  final Color ok;
  final Color bad;
  final Brightness brightness;

  const AppColors({
    required this.bg,
    required this.card,
    required this.line,
    required this.text,
    required this.mute,
    required this.gold,
    required this.goldBg,
    required this.ok,
    required this.bad,
    required this.brightness,
  });

  // Dark (default)
  static const dark = AppColors(
    bg: Color(0xFF0E0E0F),
    card: Color(0xFF1D1D1F),
    line: Color(0xFF34343A),
    text: Color(0xFFEDEAE0),
    mute: Color(0xFFA9A595),
    gold: Color(0xFFFFC61A),
    goldBg: Color(0xFF2E2608),
    ok: Color(0xFF5FD282),
    bad: Color(0xFFFF8A80),
    brightness: Brightness.dark,
  );

  // Soft light (cream & warm dark)
  static const light = AppColors(
    bg: Color(0xFFF6F4EE),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFD8D3C5),
    text: Color(0xFF1C1A14),
    mute: Color(0xFF5D5848),
    gold: Color(0xFF9A6B00),
    goldBg: Color(0xFFFFF0C2),
    ok: Color(0xFF1D7A3A),
    bad: Color(0xFFB3261E),
    brightness: Brightness.light,
  );

  // Calm (muted dark)
  static const calm = AppColors(
    bg: Color(0xFF161618),
    card: Color(0xFF222226),
    line: Color(0xFF3B3B42),
    text: Color(0xFFDCD9D0),
    mute: Color(0xFF8A877C),
    gold: Color(0xFFE5B520),
    goldBg: Color(0xFF272314),
    ok: Color(0xFF55BA76),
    bad: Color(0xFFE57373),
    brightness: Brightness.dark,
  );

  Color get done => ok;

  static AppColors of(String themeKey) {
    switch (themeKey) {
      case 'light':
        return light;
      case 'calm':
        return calm;
      case 'dark':
      default:
        return dark;
    }
  }
}

// Atkinson Hyperlegible typography helper
TextStyle appFont({
  double fontSize = 18.0,
  FontWeight fontWeight = FontWeight.w400,
  Color? color,
  double? height = 1.4,
  double? letterSpacing,
  FontStyle? fontStyle,
}) {
  try {
    return GoogleFonts.atkinsonHyperlegible(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
    );
  } catch (_) {
    // Fallback if offline
    return TextStyle(
      fontFamily: 'sans-serif',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
    );
  }
}

// 12 bucket icons
const Map<String, IconData> kBucketIcons = {
  'folder': Icons.folder_outlined,
  'book': Icons.menu_book_outlined,
  'briefcase': Icons.work_outline,
  'bulb': Icons.lightbulb_outline,
  'heart': Icons.favorite_border,
  'star': Icons.star_border,
  'home': Icons.home_outlined,
  'code': Icons.code,
  'music': Icons.music_note_outlined,
  'chart': Icons.bar_chart_outlined,
  'cart': Icons.shopping_cart_outlined,
  'person': Icons.person_outline,
};

IconData getBucketIcon(String? iconKey) {
  if (iconKey == null) return Icons.folder_outlined;
  return kBucketIcons[iconKey] ?? Icons.folder_outlined;
}
