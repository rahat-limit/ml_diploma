import 'package:flutter/material.dart';

abstract class AppColors {
  // Primary Colors
  static Color primary = const Color(0xFFE53935); // Red color from design
  static Color white = const Color(0xFFFFFFFF);
  static Color black = const Color(0xFF000000);

  // Background Colors
  static Color background = const Color(0xFFFFF3F3); // Light red background
  static Color cardBackground = const Color(0xFFFFE8E8);

  // Text Colors
  static Color textPrimary = const Color(0xFF333333);
  static Color textSecondary = const Color(0xFF666666);
  static Color textHint = const Color(0xFF999999);

  // Status Colors
  static Color success = const Color(0xFF4CAF50);
  static Color error = const Color(0xFFE53935);
  static Color warning = const Color(0xFFFFB800);

  // Input Fields
  static Color inputBackground = const Color(0xFFF5F5F5);
  static Color inputBorder = const Color(0xFFE0E0E0);

  // Button Colors
  static Color buttonPrimary = const Color(0xFFE53935);
  static Color buttonSecondary = const Color(0xFFFFEBEE);

  // Divider and Border Colors
  static Color divider = const Color(0xFFEEEEEE);
  static Color border = const Color(0xFFE0E0E0);
}
