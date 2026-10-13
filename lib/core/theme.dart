import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system GROSHOP — calqué sur le web (orange #FF5E00, DM Sans, Fraunces).
class AppColors {
  AppColors._();

  // Orange de marque
  static const Color primary     = Color(0xFFFF7A00);   // ⬅️ mobile
static const Color primarySoft = Color(0x14FF7A00);   // ⬅️ ~8% de FF7A00
  static const Color primaryDark = Color(0xFFFF4500);

  // Neutres froids (repris de l'admin)
  static const Color text   = Color(0xFF0A0A2A);
  static const Color muted  = Color(0xFF8A8FA3);
  static const Color border = Color(0xFFECEEF2);
  static const Color panel  = Color(0xFFF7F8FA);
  static const Color soft   = Color(0xFFF2F4F7);
  static const Color white  = Color(0xFFFFFFFF);

  // États
  static const Color success = Color(0xFF12B76A);
  static const Color danger  = Color(0xFFE5484D);
}

class AppTheme {
  AppTheme._();

  // ⚠️ Fraunces/DM Sans via google_fonts ne peuvent PAS être `const` → getters.
  static TextStyle display({
    double size = 28,
    FontWeight weight = FontWeight.w700, // max = w900, w1000 n'existe pas
    Color? color,
  }) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.text,
        height: 1.15,
      );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      GoogleFonts.dmSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.text,
        height: 1.4,
      );

  static ThemeData get light {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.white,
      primaryColor: AppColors.primary,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.primaryDark,
        surface: AppColors.white,
        error: AppColors.danger,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      dividerColor: AppColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        foregroundColor: AppColors.text,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }
}