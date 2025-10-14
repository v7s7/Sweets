import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF6FA3),
        background: const Color(0xFFF9EFF3),
      ),
      scaffoldBackgroundColor: const Color(0xFFF9EFF3),
      useMaterial3: true,
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        titleLarge: GoogleFonts.inter(
          fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF1C1B1F)),
        titleMedium: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1C1B1F)),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF444444)),
        labelLarge: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }

  // Script-y heading used for "Donats"
  static TextStyle get scriptTitle => GoogleFonts.pacifico(
        fontSize: 26, fontWeight: FontWeight.w500, color: const Color(0xFF222222),
      );
}
