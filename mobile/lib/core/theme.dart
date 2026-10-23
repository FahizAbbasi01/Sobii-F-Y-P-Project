import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens from design/devicetrust_mobile_registry/DESIGN.md.
class AppColors {
  static const ink = Color(0xFF000D23);
  static const navy = Color(0xFF10233F);
  static const blue = Color(0xFF246BFD);
  static const blueDark = Color(0xFF0051D3);
  static const canvas = Color(0xFFF7F9FC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFF2F4F7);
  static const slate = Color(0xFF4B5563);
  static const muted = Color(0xFF75777E);
  static const outline = Color(0x1F10233F); // navy @ 12%
  static const hairline = Color(0x0F10233F); // navy @ 6%

  static const green = Color(0xFF10B981);
  static const greenText = Color(0xFF059669);
  static const greenBg = Color(0x1A10B981);
  static const amber = Color(0xFFF59E0B);
  static const amberText = Color(0xFFD97706);
  static const amberBg = Color(0x1FF59E0B);
  static const red = Color(0xFFEF4444);
  static const redText = Color(0xFFDC2626);
  static const redBg = Color(0x1FEF4444);
  static const blueBg = Color(0x1A246BFD);
  static const slateBg = Color(0x0D4B5563);
}

class AppRadius {
  static const sm = 4.0;
  static const md = 12.0; // inputs, buttons
  static const lg = 16.0; // cards, sheets
}

class AppShadows {
  static const card = [
    BoxShadow(color: Color(0x0D10233F), blurRadius: 16, offset: Offset(0, 4), spreadRadius: -2),
    BoxShadow(color: Color(0x0810233F), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const raised = [
    BoxShadow(color: Color(0x2E246BFD), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -2),
  ];
}

class AppText {
  static TextStyle get headlineXl => GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, height: 34 / 28, color: AppColors.ink);
  static TextStyle get headlineLg => GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, height: 28 / 22, color: AppColors.ink);
  static TextStyle get headlineMd => GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, height: 24 / 18, color: AppColors.ink);
  static TextStyle get bodyLg => GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5, color: AppColors.ink);
  static TextStyle get bodyMd => GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, height: 20 / 14, color: AppColors.slate);
  static TextStyle get bodySm => GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, height: 16 / 12, color: AppColors.slate);
  static TextStyle get labelLg => GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, height: 18 / 14, color: AppColors.ink);
  static TextStyle get labelMd => GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, height: 16 / 12, color: AppColors.slate);
  static TextStyle get labelSm => GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, height: 14 / 10, letterSpacing: 0.6, color: AppColors.slate);
  static TextStyle get monoImei => GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.w500, height: 20 / 15, color: AppColors.ink);
  static TextStyle get monoData => GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w400, height: 16 / 12, color: AppColors.slate);
  static TextStyle get price => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    primary: AppColors.blue,
    onPrimary: Colors.white,
    secondary: AppColors.navy,
    error: AppColors.redText,
    surface: AppColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: GoogleFonts.interTextTheme(),
  );
}
